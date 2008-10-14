
// #version 110
// #extension all : enable

// turn "on" optimizations
#pragma optimize(on)


// #ifndef __GLSL_CG_DATA_TYPES
//     #error cg data type not defined
    #define half float
    #define half2 vec2
    #define half3 vec3
    #define half4 vec4
// #endif


#ifndef EXPE_EWA_HINT
    #define EXPE_EWA_HINT 0
#endif

#ifndef EXPE_DEPTH_INTERPOLATION
    #define EXPE_DEPTH_INTERPOLATION 0
#endif

#define EXPE_DEFERRED_SHADING

//--------------------------------------------------------------------------------
// shared variables
//--------------------------------------------------------------------------------

// custom vertex attributes
attribute float radius;

#ifdef CLIPPED_SPLAT
attribute vec3 secondNormal;
varying vec4 clipLine;
#endif

// standard uniforms
uniform float expeRadiusScale;
uniform float expePreComputeRadius;
uniform float expeDepthOffset;

// varying
varying vec4 covmat;
varying vec3 fragNormal;

varying vec3 fragNoverCdotN;
varying vec3 fragCenter;
varying float scaleSquaredDistance;

#ifdef EXPE_DEPTH_CORRECTION_VISIBILITY
varying float depthOffset;
#endif

uniform vec2 halfVp;
uniform float oneOverEwaRadius;


// for backface shading
// #undef EXPE_EARLY_BACK_FACE_CULLING
// #define EXPE_EWA_HINT 2

//--------------------------------------------------------------------------------
// Visibility Splatting
//    Vertex Shader
//--------------------------------------------------------------------------------

#ifdef __VisibilityVP__
varying vec2 scaledFragCenter2d;
void VisibilityVP(void)
{
    vec3 normal = normalize(gl_NormalMatrix * gl_Normal);
    // Point in eye space
    vec4 ePos = gl_ModelViewMatrix * gl_Vertex;

    float dotpn = dot(normal.xyz,ePos.xyz);

    vec4 oPos;
    
    #ifdef EXPE_EARLY_BACK_FACE_CULLING
    // back_face culling
    oPos = vec4(0,0,1,0);
    if(dotpn<0.)
    {
    #endif

    radius =  radius * expeRadiusScale;

    vec4 pointSize;
    pointSize.x = radius * expePreComputeRadius / ePos.z;
    gl_PointSize = max(1.0, pointSize.x);
    
    scaleSquaredDistance = 1.0 / (radius * radius);
    //fragNormal = normal;
    fragCenter = ePos.xyz;
    fragNoverCdotN = normal/dot(ePos.xyz,normal);

    #ifndef EXPE_DEPTH_CORRECTION_VISIBILITY
    ePos.xyz += normalize(ePos.xyz) * expeDepthOffset * radius;
    #else
    //ePos.xyz += normalize(ePos.xyz) * expeDepthOffset * radius;
    depthOffset = expeDepthOffset * radius;
    #endif
    
    oPos = gl_ProjectionMatrix * ePos;
    
    #if (EXPE_EWA_HINT>0)
    scaledFragCenter2d = 0.5*((oPos.xy/oPos.w)+1.0)*halfVp*oneOverEwaRadius;
    #endif

    #ifndef EXPE_EARLY_BACK_FACE_CULLING
    oPos.w = oPos.w * (dotpn<0. ? 1 : 0);
    #else
    }
    #endif
    
    gl_Position = oPos;
}

#endif

//--------------------------------------------------------------------------------
// Visibility Splatting
//    Fragment Shader
//--------------------------------------------------------------------------------

#ifdef __VisibilityFP__
varying vec2 scaledFragCenter2d;
uniform vec3 rayCastParameter1;
uniform vec3 rayCastParameter2;
uniform vec2 depthParameterCast;

void VisibilityFP(void)
{
    // compute q in object space
    vec3 qOne = rayCastParameter1 * gl_FragCoord.xyz + rayCastParameter2; // MAD
    float oneOverDepth = dot(qOne,-fragNoverCdotN); // DP3
    float depth = (1.0/oneOverDepth); // RCP
    vec3 diff = fragCenter + qOne * depth; // MAD
    float r2 = dot(diff,diff); // DP3
    
    #if (EXPE_EWA_HINT>0)
    vec2 d2 = oneOverEwaRadius*gl_FragCoord.xy - scaledFragCenter2d; // MAD
    float r2d = dot(d2,d2); // DP3
    gl_FragColor = min(r2d,r2*scaleSquaredDistance);
    #else
    gl_FragColor = r2*scaleSquaredDistance;
    #endif

    

    #ifdef EXPE_DEPTH_CORRECTION_VISIBILITY
    oneOverDepth = 1.0/(-depth+depthOffset);
    gl_FragDepth = depthParameterCast.x * oneOverDepth + depthParameterCast.y; // MAD
    #endif
}

#endif

#ifdef __AttributeVP__

// #define EXPE_LIGHTING
// vec4 expeLighting(vec4 color, vec3 eyePos, vec3 normal, vec3 shadowCoeff)
// {
//     return color * clamp(normal.x,0.f,1.f) + 0.5*clamp(normal.y,0.f,1.f);
// }

varying vec2 scaledFragCenter2d;

void AttributeVP(void)
{
    // transform normal
    vec3 normal = normalize(gl_NormalMatrix * gl_Normal);
    // Point in eye space
    vec4 ePos = gl_ModelViewMatrix * gl_Vertex;
    
    float dotpn = dot(normal.xyz,ePos.xyz);
    
    vec4 oPos;

    #ifdef EXPE_EARLY_BACK_FACE_CULLING
    // back_face culling
    oPos = vec4(0,0,1,0);
    if(dotpn<0.)
    {
    #endif
    
    // for backface shading
//     if(dotpn>0.)
//     {
//         dotpn = -dotpn;
//         normal = -normal;
//     }
    // end back face shading

    //vec3 p = ePos.xyz / ePos.w;
    //float pz1 = 1./p.z;

    radius = radius * expeRadiusScale;

    vec4 pointSize;
    pointSize.x = radius * expePreComputeRadius / ePos.z;
    
    #if (EXPE_EWA_HINT>0)
    //gl_PointSize = max(2, pointSize.x);
    gl_PointSize = max(2.0, pointSize.x);
    #else
    gl_PointSize = max(1.0, pointSize.x);
    #endif

    scaleSquaredDistance = 1. / (radius * radius);
    fragNormal = normal;
    fragCenter = ePos.xyz;
    fragNoverCdotN = normal/dot(ePos.xyz,normal);

    // Output color
    #ifdef EXPE_DEFERRED_SHADING
        fragNormal.xyz = normal.xyz;
        gl_FrontColor = gl_Color;
    #else
        // Output color
        #ifdef EXPE_LIGHTING
        gl_FrontColor = expeLighting(gl_Color, ePos.xyz, normal.xyz, 1.);
        #else
        gl_FrontColor = gl_Color;
        #endif
    #endif

    oPos = gl_ModelViewProjectionMatrix * gl_Vertex;

    #if (EXPE_EWA_HINT>0)
    scaledFragCenter2d = ((oPos.xy/oPos.w)+1.0)*halfVp*oneOverEwaRadius;
    #endif

//     pointSize.w = dot(mvpt[3], gl_Vertex);

    #ifndef EXPE_EARLY_BACK_FACE_CULLING
    oPos.w = oPos.w * (dotpn<0. ? 1 : 0);
    #else
    }
    #endif
    
    gl_Position = oPos;
}

#endif

//--------------------------------------------------------------------------------
// EWA Splatting
//    Fragment Shader
//--------------------------------------------------------------------------------

#ifdef __AttributeFP__
// this sampler is only used by this fragment shader

varying vec2 scaledFragCenter2d;
uniform vec3 rayCastParameter1;
uniform vec3 rayCastParameter2;
uniform vec2 depthParameterCast;

uniform sampler1D Kernel1dMap;

void AttributeFP(void)
{
    vec3 qOne = rayCastParameter1 * gl_FragCoord.xyz + rayCastParameter2; // MAD
    float oneOverDepth = dot(qOne,fragNoverCdotN); // DP3
    float depth = (1.0/oneOverDepth); // RCP
    vec3 diff = fragCenter - qOne * depth; // MAD
    float r2 = dot(diff,diff); // DP3

    #if (EXPE_EWA_HINT>0)
    vec2 d2 = oneOverEwaRadius*gl_FragCoord.xy - scaledFragCenter2d; // MAD
    float r2d = dot(d2,d2); // DP3
//     float weight = texture1D(Kernel1dMap, min(r2d,r2*scaleSquaredDistance)).a; // MUL + MIN + TEX
    float weight = min(r2d,r2*scaleSquaredDistance);
    weight = clamp(1.-weight,0,1);
    weight = weight*weight;
    #else
    //float weight = texture1D(Kernel1dMap, r2*scaleSquaredDistance).a; // MUL + TEX
    float weight = clamp(1.-r2*scaleSquaredDistance,0,1);
    weight = weight*weight;
    #endif
    
    #ifdef EXPE_DEPTH_CORRECTION_ATTRIB
    gl_FragDepth = depthParameterCast.x * oneOverDepth + depthParameterCast.y; // MAD
    #endif
    
    #ifdef EXPE_DEFERRED_SHADING
    gl_FragData[0].rgb = gl_Color.rgb; // MOV
    gl_FragData[1].xyz = fragNormal.xyz; // MOV
    gl_FragData[1].w = weight; // MOV
    gl_FragData[0].w = weight;
    
    #if EXPE_DEPTH_INTERPOLATION==2 // linear space
        gl_FragData[1].z = -depth; // MOV
    #elif EXPE_DEPTH_INTERPOLATION==1 // window space
        #ifdef EXPE_DEPTH_CORRECTION_ATTRIB
        gl_FragData[1].z = gl_FragDepth;
        #else
        gl_FragData[1].z = gl_FragCoord.z;
        #endif
    #endif
    
    #else
    gl_FragColor.rgb = gl_Color.rgb; // MOV
    gl_FragColor.w = weight;
    #endif

}

#endif
