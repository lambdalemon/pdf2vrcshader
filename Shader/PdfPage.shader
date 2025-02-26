Shader "Geometry/PdfPage"
{
	Properties
	{
        _MainTex ("MainTex", 2D) = "" {}
		[Toggle]_HALF ("Half Precision", Float) = 0
		[Toggle]_EXACT_BEZIER ("Exact Bezier Strokes (Slower)", Float) = 0


        [Space(30)]
		[Toggle]_PACKED_ATLAS ("Packed Atlas", Float) = 0
		[HideIfEnabled(_PACKED_ATLAS_ON)]_GlyphAtlas ("Glyph Atlas", 2DArray) = "" {}
		[HideIfEnabled(_PACKED_ATLAS_ON)]_Padding ("Padding", Float) = 2.5
		[HideIfEnabled(_PACKED_ATLAS_ON)]_PlaneBounds ("PlaneBounds", Vector) = (0, 0, 1, 1)
		[HideIfDisabled(_PACKED_ATLAS_ON)]_GlyphAtlasPacked ("Glyph Atlas", 2D) = "" {}

		[Space(20)]
		_AtlasOffset ("Atlas Offset", Integer) = 0
		_OffsetZ ("OffsetZ", Float) = 0.0001
		_NumTrisPerPage ("Number of Triangles", Integer) = 146
		_NumPages ("Number of Pages", Integer) = 921
		_PageNumberOffset ("Page Number Offset", Float) = 0
		_PageNumberOffsetIncrement ("Page Number Offset Increment", Integer) = 2

		[Space(20)]
		[Toggle]_COLOR ("Use Color", Float) = 0
		[HideIfEnabled(_COLOR_ON)][HDR]_Color ("Text Color", Color) = (0, 0, 0, 1)
		[HideIfDisabled(_COLOR_ON)][HDR]_ColorTex ("Color", 2D) = "" {}

		[Space(20)]
		_ImageAtlas ("Image Atlas", 2D) = "" {}

		[Space(20)]
		[Toggle]_DIFFUSE ("Diffuse", Float) = 0
	}
	SubShader
	{
		Tags { "Queue"="AlphaTest" "LightMode"="ForwardBase" }

		LOD 100

		CGINCLUDE
		#include "UnityCG.cginc"
		#ifdef _DIFFUSE_ON
		#include "Lighting.cginc"
		#include "AutoLight.cginc"
		#endif

		struct v2g {
			float4 vertex : SV_POSITION;
			float4 offsets : TEXCOORD0;
			float4 tangent : TEXCOORD1;
			float4 binormal : TEXCOORD2;
			float4 normal : TEXCOORD3;
		};

		struct g2f {
			float4 pos : SV_POSITION;
			float4 uvt : TEXCOORD0;
			float2 bStroke : TEXCOORD1;
		#ifdef _DIFFUSE_ON
			SHADOW_COORDS(2)
		#endif
		#ifdef _COLOR_ON
			float4 color : COLOR0;
		#endif
		#ifdef _DIFFUSE_ON
			fixed3 diff : COLOR1;
			fixed3 ambient : COLOR2;
		#endif
		};

		Texture2D _MainTex;
		float4 _MainTex_TexelSize;
		
		#ifdef _PACKED_ATLAS_ON
		UNITY_DECLARE_TEX2D(_GlyphAtlasPacked);
		float4 _GlyphAtlasPacked_TexelSize;
		#else
		UNITY_DECLARE_TEX2DARRAY(_GlyphAtlas);
		float4 _GlyphAtlas_TexelSize;
		float _Padding;
		float4 _PlaneBounds;
		#endif

		float _OffsetZ;
		uint _AtlasOffset, _NumTrisPerPage, _NumPages, _PageNumberOffset, _PageNumberOffsetIncrement;

		#ifdef _COLOR_ON
		Texture2D _ColorTex;
		#else
		float4 _Color;
		#endif

		UNITY_DECLARE_TEX2D(_ImageAtlas);

		float4 loadData(Texture2D tex, uint offset) {
			uint2 coord = uint2(offset % _MainTex_TexelSize.z, offset / _MainTex_TexelSize.z);
			return tex.Load(int3(coord.xy, 0));
		}

		v2g vert(appdata_tan i) {
			v2g o;
			uint pageNumber = i.texcoord.x + _PageNumberOffset * _PageNumberOffsetIncrement;
			if (0 <= pageNumber && pageNumber < _NumPages) {
				uint dataOffset = _AtlasOffset + pageNumber;
		#ifdef _HALF_ON
				uint4 offsets = f32tof16(loadData(_MainTex, dataOffset));
				offsets.x = offsets.x << 14 | offsets.w;
				offsets.w = 0;
				o.offsets = offsets;
		#else
				o.offsets = loadData(_MainTex, dataOffset);
		#endif
			} else {
				o.offsets = 0;
			}
			o.vertex = i.vertex;
			o.tangent = float4(i.tangent.xyz, 0);
			o.normal = float4(i.normal, 0);
			o.binormal = float4(cross(normalize(i.normal), i.tangent.xyz) * i.tangent.w, 0);

			// Early backface culling
			float4 pageToCamera = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)) - i.vertex;
			if (dot(pageToCamera, o.normal) < 0) {
				o.offsets = 0;
			}
			return o;
		}

		void addGeomVert(inout g2f o, float4x4 pageToObject, float2 pxy, float2 uxy) {
			o.uvt.xy = uxy;
			o.pos = UnityObjectToClipPos(mul(float4(pxy, _OffsetZ, 1), pageToObject));
		#ifdef _DIFFUSE_ON
			TRANSFER_SHADOW(o)
		#endif
		}

		[maxvertexcount(4)]
		[instance(32)]
		void geom(triangle v2g input[3], inout TriangleStream<g2f> triStream, uint instanceID : SV_GSInstanceID, uint geoPrimID : SV_PrimitiveId) {
			uint id = (geoPrimID % _NumTrisPerPage) * 32 + instanceID;
			uint4 pageOffsets = input[0].offsets;
			if (id >= pageOffsets.y + pageOffsets.z) {
				return;
			}

			g2f o;
			o.bStroke = 0;
			float2 pxy, pxw, pzy, pzw;
			float2 uxy, uxw, uzy, uzw;
			bool isUprightChar = id < pageOffsets.y;
			uint dataOffset = isUprightChar ? pageOffsets.x + id : pageOffsets.x - pageOffsets.y + 2 * id;
			float4 data0 = loadData(_MainTex, dataOffset);
			float4 data1 = loadData(_MainTex, dataOffset + 1);
		#ifdef _COLOR_ON
			o.color = loadData(_ColorTex, dataOffset);
		#endif
			o.uvt.zw = isUprightChar ? 0 : data1.zw;
			int type = isUprightChar ? 0 : data1.w;

		#ifdef _DIFFUSE_ON
			half3 worldNormal = UnityObjectToWorldNormal(input[0].normal);
			half nl = max(0, dot(worldNormal, _WorldSpaceLightPos0.xyz));
			o.diff = nl * _LightColor0.rgb;
			o.ambient = ShadeSH9(half4(worldNormal,1));
		#endif

			switch(type) {
				case 0: {
					uint glyphId = isUprightChar ? data0.w : data1.z;
		#ifdef _PACKED_ATLAS_ON
					float4 planeBounds = loadData(_MainTex, 2 * glyphId);
					float4 uvBounds = loadData(_MainTex, 2 * glyphId + 1);
		#else
					o.uvt.z = glyphId;
					float4 planeBounds = _PlaneBounds;
					float2 cellBounds = float2(_Padding, _GlyphAtlas_TexelSize.z - _Padding) * _GlyphAtlas_TexelSize.x;
					float4 uvBounds = cellBounds.xxyy;
		#endif
					float2x2 mat = isUprightChar ? float2x2(data0.z, 0, 0, data0.z) : data0;
					float2 origin = isUprightChar ? data0.xy : data1.xy;
					pxy = mul(planeBounds.xy, mat) + origin;
					pxw = mul(planeBounds.xw, mat) + origin;
					pzy = mul(planeBounds.zy, mat) + origin;
					pzw = mul(planeBounds.zw, mat) + origin;
					uxy = uvBounds.xy;
					uxw = uvBounds.xw;
					uzy = uvBounds.zy;
					uzw = uvBounds.zw;
				}
				break;
				case 1: {
					float linewidth = data1.x;
					float2 linedir = normalize(data0.zw - data0.xy);
					float2 normal = linewidth * float2(-linedir.y, linedir.x);
					pxy = data0.xy - normal;
					pxw = data0.xy + normal;
					pzy = data0.zw - normal;
					pzw = data0.zw + normal;				
					uxy = -1;
					uxw = 1;
					uzy = -1;
					uzw = 1;
				}
				break;
				case 2: {
					o.bStroke = data1.xy;
					o.uvt.w = (data1.z > 0.5) || (data1.y < 1e-4) ? 3 : 2;
					float2 linedir = data0.zw - data0.xy;
					float2 normal = float2(-linedir.y, linedir.x);
					float leftPadX = 0.5 * min(data1.x, 0) - data1.z;
					float rightPadX = 0.5 * max(data1.x - 1, 0) + data1.z;
					float minY = -data1.z;
					float maxY = 0.5 * data1.y + data1.z;
					pxy = data0.xy + normal * minY + leftPadX * linedir;
					pxw = data0.xy + normal * maxY + leftPadX * linedir;
					pzy = data0.zw + normal * minY + rightPadX * linedir;
					pzw = data0.zw + normal * maxY + rightPadX * linedir;
					uxy = float2(leftPadX, minY);
					uxw = float2(leftPadX, maxY);
					uzy = float2(1 + rightPadX, minY);
					uzw = float2(1 + rightPadX, maxY);
				}
				break;
				case 2048: {
					float2x2 mat = data0;
					float2 origin = data1.xy;
					float4 planeBounds = float4(0, 0, 1, 1);
					float4 uvBounds = loadData(_MainTex, data1.z);
					pxy = mul(planeBounds.xy, mat) + origin;
					pxw = mul(planeBounds.xw, mat) + origin;
					pzy = mul(planeBounds.zy, mat) + origin;
					pzw = mul(planeBounds.zw, mat) + origin;
					uxy = uvBounds.xy;
					uxw = uvBounds.xw;
					uzy = uvBounds.zy;
					uzw = uvBounds.zw;
				}
				break;
				case -1: {
					pxy = data1.xy;
					pxw = data0.xy;
					pzy = data0.zw;
					pzw = pxy;
					uxy = float2(0.5, 0);
					uxw = 0;
					uzy = 1;
					uzw = uxy;
				}
				break; 
				default: {
					pxy = data1.xy;
					pxw = data0.xy;
					pzy = data0.zw;
					pzw = pxy;
					o.uvt.w = 1;
					int uu = -data1.w;
					uxy = (float((uu >> 4) & 3) - 1) * 0.5;
					uxw = (float(uu & 3) - 1) * 0.5;
					uzy = (float((uu >> 2) & 3) - 1) * 0.5;
					uzw = uxy;						
				}
				break;
			}

			float4x4 pageToObject = float4x4(input[0].tangent, input[0].binormal, input[0].normal, input[0].vertex);
			addGeomVert(o, pageToObject, pxy, uxy);
			triStream.Append(o);
			addGeomVert(o, pageToObject, pxw, uxw);
			triStream.Append(o);
			addGeomVert(o, pageToObject, pzy, uzy);
			triStream.Append(o);
			addGeomVert(o, pageToObject, pzw, uzw);
			triStream.Append(o);
		}

		float median(float r, float g, float b) {
			return max(min(r, g), min(max(r, g), b));
		}

		// Copyright (c) 2014 - 2024 Viktor Chlumsky
		// https://github.com/Chlumsky/msdfgen
		float msdf(float3 uv) {
		#ifdef _PACKED_ATLAS_ON
			float2 atlasTexelSize = _GlyphAtlasPacked_TexelSize.x;
		#else
			float2 atlasTexelSize = _GlyphAtlas_TexelSize.x;
		#endif
			float2 screenTexSize = 1. / fwidth(uv.xy);
			float screenPxRange = atlasTexelSize * (screenTexSize.x + screenTexSize.y);
			float mipLevel = max(0, -log2(screenPxRange));			
		#ifdef _PACKED_ATLAS_ON
			float3 msd = UNITY_SAMPLE_TEX2D_LOD(_GlyphAtlasPacked, uv.xy, mipLevel).rgb;
		#else
			float3 msd = UNITY_SAMPLE_TEX2DARRAY_LOD(_GlyphAtlas, uv, mipLevel).rgb;
		#endif
			float sd = median(msd.r, msd.g, msd.b);			
			float screenPxDistance = max(screenPxRange, 1.) * (sd - 0.5);
			float alpha = saturate(screenPxDistance + 0.5);
			return alpha;
		}

		float lineSdf(float y) {
			float sd = (abs(y) - 0.5) / length(float2(ddx(y), ddy(y)));
			return saturate(0.5 - sd);
		}

		float lineRoundCapSdf(float2 p, float lw) {
			float2 d = p - float2(saturate(p.x), 0);
			float len_d = length(d);
			float sd = (len_d - 0.5 * lw) / (abs(dot(ddx(p), d)) + abs(dot(ddy(p), d))) * len_d;
			float alpha = saturate(0.5 - sd);
			return alpha;
		}

		// https://www.microsoft.com/en-us/research/wp-content/uploads/2005/01/p1000-loop.pdf
		float bezierFill(float2 p, float sign) {
			float2 d = float2(2 * p.x, -1);
			float2 grad = float2(dot(ddx(p), d), dot(ddy(p), d));
			float sd = (p.x * p.x - p.y) / length(grad) * sign;
			float alpha = saturate(0.5 - sd);
			return alpha;
		}

		// Copyright © 2018 Inigo Quilez
		#ifdef _EXACT_BEZIER_ON
		// https://www.shadertoy.com/view/WltSD7
		float cos_acos_3( float x ) { 
			x=sqrt(0.5+0.5*x); 
			return x*(x*(x*(x*-0.008972+0.039071)-0.107074)+0.576975)+0.5; 
		}

		float bezierStroke( float2 pos, float2 B, float lw ) {    
			float2 a = B;
			float2 b = - 2.0*B + float2(1,0);
			float2 c = a * 2.0;
			float2 d = - pos;
		
			// cubic to be solved (kx*=3 and ky*=3)
			float kk = 1.0/dot(b,b);
			float kx = kk * dot(a,b);
			float ky = kk * (2.0*dot(a,a)+dot(d,b))/3.0;
			float kz = kk * dot(d,a);      
		
			float p  = ky - kx*kx;
			float q  = kx*(2.0*kx*kx - 3.0*ky) + kz;
			float p3 = p*p*p;
			float q2 = q*q;
			float h  = q2 + 4.0*p3;
		
			float len_dd;
			float2 dd;
		
			if( h>=0.0 ) {
				// 1 root
				h = sqrt(h);
				float2 x = (float2(h,-h)-q)/2.0;
				float2 uv = sign(x)*pow(abs(x), 1.0/3.0);
				float t = uv.x + uv.y;
				// from NinjaKoala - single newton iteration to account for cancellation
				t -= (t*(t*t+3.0*p)+q)/(3.0*t*t+3.0*p);
				t = saturate( t-kx );
				dd = d+(c+b*t)*t;
				len_dd = length(dd);
			} else {
				// 3 roots
				float z = sqrt(-p);
				float m = cos_acos_3( q/(p*z*2.0) );
				float n = sqrt(1.0-m*m);
				n *= sqrt(3.0);
				float3  t = saturate( float3(m+m,-n-m,n-m)*z-kx );
				float2  qx=d+(c+b*t.x)*t.x; float dx=dot(qx,qx);
				float2  qy=d+(c+b*t.y)*t.y; float dy=dot(qy,qy);
				dd = dx<dy ? qx : qy;
				len_dd = sqrt(min(dx, dy));
			}

			float2 sd = (len_dd - 0.5 * lw) / (abs(dot(ddx(pos), dd)) + abs(dot(ddy(pos), dd))) * len_dd;
			float alpha = saturate(0.5 - sd);
		
			return alpha;
		}
		#else
		// This method provides just an approximation, and is only usable in
		// the very close neighborhood of the curve. Taken and adapted from
		// http://research.microsoft.com/en-us/um/people/hoppe/ravg.pdf
		float det(float2 a, float2 b) { 
			return a.x * b.y - a.y * b.x;
		}

		float bezierStroke(float2 p, float2 c, float lw) {
			float2 i = float2(1,0);
			float2 j = i-c;
			float2 w = j-c;
			float2 v0 = -p;
			float2 v1 = c-p;
			float2 v2 = i-p;	
			
			float x = det(v0, v2);
			float y = det(v1, v0);
			float z = det(v2, v1);
		
			float2 s = 2*(y*j+z*c)+x*i;
		
			float r = (y*z-x*x*0.25) / dot(s,s);
			float t = saturate((0.5*x+y+r*dot(s,w)) / c.y);
			float2 d = v0+t*(c+c+t*w);
			float len_d = length(d);

			float sd = (len_d - 0.5 * lw) / (abs(dot(ddx(p), d)) + abs(dot(ddy(p), d))) * len_d;
			float alpha = saturate(0.5 - sd);
			
			return alpha;
		}
		#endif

		float4 albedo(g2f i) {
			int type = round(i.uvt.w);
		#ifdef _COLOR_ON
			float3 color = i.color.rgb;
		#else
			float3 color = _Color.rgb;
		#endif
			switch(type) {
				case 0:
					return float4(color, msdf(i.uvt.xyz));
				case 1:
					return float4(color, lineSdf(i.uvt.y));
				case 2:
					return float4(color, bezierStroke(i.uvt.xy, i.bStroke.xy, i.uvt.z));
				case 3:
					return float4(color, lineRoundCapSdf(i.uvt.xy, i.uvt.z));
				case 2048:
					return UNITY_SAMPLE_TEX2D(_ImageAtlas, i.uvt.xy);
				case -1:
					return float4(color, bezierFill(i.uvt.xy, i.uvt.z));
				default:
					return 0;
			}
		}

		float4 frag(g2f i) : SV_Target {
		#ifdef _DIFFUSE_ON
			float4 color = albedo(i);
			color.rgb *= i.diff * LIGHT_ATTENUATION(i) + i.ambient;
			return color;
		#else
			return albedo(i);
		#endif
		}
		ENDCG

		Pass
		{
        	ZWrite Off
        	Blend SrcAlpha OneMinusSrcAlpha
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma geometry geom
			#pragma target 5.0
			#pragma shader_feature_local _PACKED_ATLAS_ON
			#pragma shader_feature_local _HALF_ON
			#pragma shader_feature_local _COLOR_ON
			#pragma shader_feature_local _EXACT_BEZIER_ON
			#pragma shader_feature_local _DIFFUSE_ON
			#pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight	
			ENDCG
		}
	}
}
