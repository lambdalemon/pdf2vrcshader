using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

[CustomEditor(typeof(PdfPageMeshCreator))]
public class PdfPageMeshCreatorEditor : Editor
{
    public override void OnInspectorGUI() {
        DrawDefaultInspector();
        if(GUILayout.Button("Create Mesh"))
            ((PdfPageMeshCreator)target).createMesh();
    }
}
