#if UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Unity.Collections;
using UnityEditor;

public class PdfPageMeshCreator : MonoBehaviour
{   
    public float pageWidth, pageHeight;
    public int numTriangles, startPage, endPage;
    public bool doubleSided, startOnBackside;
    public enum BonePlacement {
        Center,
        BottomLeft,
        BottomRight,
        TopLeft,
        TopRight
    }
    public BonePlacement bonePlacement;
    public bool includeBackground;

    public void createMesh()
    {   
        if (endPage < startPage) {
            Debug.LogError("End Page can't be smaller than Start Page!");
            return;
        }

        float pageScale = Math.Max(pageWidth, pageHeight);
        float halfWidth = 0.5f * pageWidth / pageScale;
        float halfHeight = 0.5f * pageHeight / pageScale;
    
        int numPages = endPage - startPage + 1;
        int numBones = doubleSided ? (endPage - startPage + (startOnBackside ? 1 : 0)) / 2 + 1 : numPages;
        int numVerticesPerPage = doubleSided ? 5 : 9;
        int numVertices = numPages * numVerticesPerPage;
        Vector3[] vertices = new Vector3[numVertices];
        Vector2[] uvs = new Vector2[numVertices];
        Vector3[] normals = new Vector3[numVertices];
        Vector4[] tangents = new Vector4[numVertices];
        BoneWeight1[] weights = new BoneWeight1[numVertices];
        byte[] bonesPerVertex = new byte[numVertices];
        int[] triangles0 = new int[numPages * numTriangles * 3];
        int sizeTris1 = doubleSided ? 6 : 12;
        int[] triangles1 = new int[numPages * sizeTris1];
        int[] pageTris1 = new int[] {3, 4, 2, 3, 2, 1, 7, 8, 6, 7, 6, 5};

        for (int i = 0; i < numPages; i++) {
            int boneId = doubleSided ? (i + (startOnBackside ? 1 : 0)) / 2 : i;
            for (int j = 0; j < numVerticesPerPage; j++) {
                int vertexId = i + j * numPages;
                float side = (doubleSided ? ((i & 1) == 0) ^ startOnBackside : j < 5) ? 1 : -1;
                if (j == 0) {
                    vertices[vertexId] = Vector3.zero;
                    uvs[vertexId] = new Vector2(startPage + i, 0);
                } else {
                    bool isLeft = ((j - 1) & 1) == 0;
                    bool isBottom = ((j - 1) & 2) == 0;
                    vertices[vertexId] = new Vector3((isLeft ? -1 : 1) * halfWidth * side, (isBottom ? -1 : 1) * halfHeight, 0);
                    uvs[vertexId] = new Vector2(isLeft ? 0 : 1, isBottom ? 0 : 1);
                }
                normals[vertexId] = new Vector3(0, 0, -side);
                tangents[vertexId] = new Vector4(side, 0, 0, -1);
                weights[vertexId].boneIndex = boneId;
                weights[vertexId].weight = 1;
                bonesPerVertex[vertexId] = 1;
            }
            for (int j = 0; j < numTriangles * 3; j++) {
                triangles0[j + i * numTriangles * 3] = i;
            }
            for (int j = 0; j < sizeTris1; j++) {
                triangles1[j + i * sizeTris1] = i + pageTris1[j] * numPages;
            }
        }
    
        Mesh mesh = new Mesh();
        mesh.subMeshCount = includeBackground ? 2 : 1;
        mesh.SetVertices(vertices);
        mesh.SetUVs(0, uvs);
        mesh.SetTriangles(triangles0, 0);
        if (includeBackground) {
            mesh.SetTriangles(triangles1, 1);
        }
        mesh.SetNormals(normals);
        mesh.SetTangents(tangents);

        Material[] mats;
        if (includeBackground) {
            Material bgMaterial = (Material)AssetDatabase.LoadAssetAtPath("Assets/lambdalemon/PdfPage/Material/Background.mat", typeof(Material));
            mats = new Material[] { null, bgMaterial };
        } else {
            mats = new Material[] { null };
        }

        if (numBones > 1) {
            var bonesPerVertexArray = new NativeArray<byte>(bonesPerVertex, Allocator.Temp);
            var weightsArray = new NativeArray<BoneWeight1>(weights, Allocator.Temp);
            mesh.SetBoneWeights(bonesPerVertexArray, weightsArray);
            bonesPerVertexArray.Dispose();
            weightsArray.Dispose();

            Vector3 bonePosition = bonePlacement switch {
                BonePlacement.Center      => Vector3.zero,
                BonePlacement.BottomLeft  => new Vector3(-halfWidth, -halfHeight, 0),
                BonePlacement.BottomRight => new Vector3( halfWidth, -halfHeight, 0),
                BonePlacement.TopLeft     => new Vector3(-halfWidth,  halfHeight, 0),
                BonePlacement.TopRight    => new Vector3( halfWidth,  halfHeight, 0),
                _                         => Vector3.zero
            };
            Matrix4x4[] bindPoses = new Matrix4x4[numBones];            
            Transform[] bones = new Transform[numBones];
            for (int i = 0; i < numBones; i++) {
                bones[i] = new GameObject("Bone " + i.ToString()).transform;
                bones[i].parent = transform;
                bones[i].localRotation = Quaternion.identity;
                bones[i].localPosition = bonePosition;
                bones[i].localScale = new Vector3(1, 1, 1);
                bindPoses[i] = bones[i].worldToLocalMatrix * transform.localToWorldMatrix;
            }
            mesh.bindposes = bindPoses;

            gameObject.AddComponent<SkinnedMeshRenderer>();
            SkinnedMeshRenderer rend = GetComponent<SkinnedMeshRenderer>();
            rend.materials = mats;
            rend.bones = bones;
            rend.sharedMesh = mesh;
        } else {
            gameObject.AddComponent<MeshRenderer>();
            gameObject.AddComponent<MeshFilter>();
            MeshFilter filter = GetComponent<MeshFilter>();
            filter.sharedMesh = mesh;
            MeshRenderer rend = GetComponent<MeshRenderer>();
            rend.materials = mats;
        }

        string pageType = doubleSided ? (startOnBackside ? "DB" : "D") : "S";
        string bg = includeBackground ? "BG" : "noBG";
        string path = $"Assets/lambdalemon/PdfPage/Mesh/W{pageWidth}-H{pageHeight}-T{numTriangles}-P{startPage}-{endPage}-{pageType}-{bonePlacement}-{bg}.asset";
		AssetDatabase.CreateAsset(mesh, path);
    }
}
#endif
