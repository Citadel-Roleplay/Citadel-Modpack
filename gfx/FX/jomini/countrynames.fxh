Includes = {
	"cw/camera.fxh"
	"cw/upscale_utils.fxh"
}
ConstantBuffer( PdxConstantBuffer0 )
{
	float	Transparency;
	float	OffsetX;
	float2	TextureSize;
	float	LodFactor;
	float	ThicknessBias;
};


VertexStruct VS_INPUT_MAPNAME
{
    float3 Position 	: POSITION;
	float2 TexCoord 	: TEXCOORD0;
};

VertexStruct VS_OUTPUT_MAPNAME
{
    float4 Position 		: PDX_POSITION;
	float3 WorldSpacePos 	: TEXCOORD0;
    float2 TexCoord			: TEXCOORD1;
	@ifdef PDX_NAMES_SHADOW_PROJ
    float4 ShadowProj		: TEXCOORD2;
	@endif
	# MOD(godherja)
	int GH_TerrainVariantIndex : TEXCOORD3;
	# END MOD
};

VertexShader =
{
	Code
	[[
		VS_OUTPUT_MAPNAME MapNameVertexShader( in VS_INPUT_MAPNAME Input, in float FlattenTo, in float FlattenAmount )
		{
			VS_OUTPUT_MAPNAME Out;
		
			Out.WorldSpacePos = Input.Position.xyz;
			Out.WorldSpacePos.y = lerp( Out.WorldSpacePos.y, FlattenTo, FlattenAmount );
			
			float4 vPos = float4( Out.WorldSpacePos, 1.0f );
			vPos.x += OffsetX;
		
			vPos = FixProjectionAndMul( ViewProjectionMatrix, vPos );
			Out.Position = vPos;
			
			Out.TexCoord = Input.TexCoord;
		
		#ifdef PDX_NAMES_SHADOW_PROJ
		Out.ShadowProj = mul( ShadowMapTextureMatrix, float4( Out.WorldSpacePos, 1.0 ) );
		#endif

			return Out;
		}
	]]
}

PixelShader = 
{
	Code
	[[
		//float CalcAlphaGrayscale( in PdxTextureSampler2D FontAtlas, in float2 UV )
		//{			
		//	float Sample = PdxTex2D( FontAtlas, UV ).r;
		//	return Sample * Transparency;
		//}
		float CalcTexelPixelRatio( float2 TextureCoordinate )
		{
			float2 DX = ApplyUpscaleNativeLodBiasMultiplier( ddx( TextureCoordinate ) );
			float2 DY = ApplyUpscaleNativeLodBiasMultiplier( ddy( TextureCoordinate ) );
			float MaxSquared = max( dot( DX, DX ), dot( DY, DY ) );
			return sqrt( MaxSquared );
		}
		float CalcAlphaDistanceField( in PdxTextureSampler2D FontAtlas, in float2 UV )
		{
			float Sample = PdxTex2DUpscaleNative( FontAtlas, UV ).r;
			
			float2 TextureCoordinate = UV * TextureSize;
			float Ratio = CalcTexelPixelRatio( TextureCoordinate );
			float HalfRange = 0.0025f + Ratio * LodFactor * 0.5f;
			float Mid = 0.5f - ThicknessBias;
			return smoothstep( Mid - HalfRange, Mid + HalfRange, Sample ) * Transparency;
		}
	]]
}