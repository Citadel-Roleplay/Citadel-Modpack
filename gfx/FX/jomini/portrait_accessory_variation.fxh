Includes = {
	"jomini/texture_decals_base.fxh"
	"jomini/portrait_user_data.fxh"
	"jomini/portrait_decals.fxh"
}

PixelShader =
{
	TextureSampler PatternMask
	{
		Ref = PdxMeshCustomTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}

	TextureSampler PatternColorPalette
	{
		Ref = PdxMeshCustomTexture1
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

	TextureSampler PatternColorMasks
	{
		Ref = PdxMeshCustomTexture2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}

	TextureSampler PatternNormalMaps
	{
		Ref = PdxMeshCustomTexture3
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}

	TextureSampler PatternPropertyMaps
	{
		Ref = PdxMeshCustomTexture4
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}

	Code
	[[
		#ifdef VARIATIONS_ENABLED
			struct SPatternOutput
			{
				float4	_Diffuse;
				float4	_Properties;
				float3	_Normal;
			};

			SPatternOutput ApplyPattern( float2 UV, SPatternDesc Desc, float RandomNumber, int MaskIndex, inout float OpacityMask )
			{
				// Rotate and scale around (0.5,0.5)
				float2 Rotate = float2( cos( Desc._Rotation ), sin( Desc._Rotation ) );
				UV -= vec2(0.5f);
				UV = float2( UV.x * Rotate.x - UV.y * Rotate.y, UV.x * Rotate.y + UV.y * Rotate.x );
				UV /= Desc._Scale;
				UV += vec2(0.5f);
				UV += Desc._Offset;
				
				float4 ColorMask = PdxTex2D( PatternColorMasks, float3( UV, Desc._ColorMaskIndex ) );
				
				float4 PatternColor = float4( 1.0f, 1.0f, 1.0f, 0 );
				float4 PatternProperties = PdxTex2D( PatternPropertyMaps, float3( UV, Desc._PropertyMapIndex ) );
				float4 PatternNormalSample = PdxTex2D( PatternNormalMaps, float3( UV, Desc._NormalMapIndex ) );

				//If there is a second color mask, the color palette size should be 32-width
				#ifdef SECOND_COLOR_MASK
					float PaletteWidth = 32.0f;
				#else
					float PaletteWidth = 16.0f;
				#endif
				
				//Sample the color palette once for each channel in the mask
				for ( int i = 0; i < 4; ++i )
				{
					if ( ColorMask[i] > 0.0f )
					{
						// Select from 16-width color palette
						float3 Sample;
						if ( PatternColorOverrides[MaskIndex + i].a > 0.0f )
						{
							Sample = PatternColorOverrides[MaskIndex + i].rgb;
						}
						else
						{
							float HorizontalSample = ( MaskIndex * 4.0f ) + i;
							HorizontalSample = ( HorizontalSample + 0.5f ) / PaletteWidth;
							Sample = PdxTex2D( PatternColorPalette, float2( HorizontalSample, RandomNumber ) ).rgb;
						}
						PatternColor.rgb = lerp( PatternColor.rgb, Sample, ColorMask[i] );
						PatternColor.a = max( PatternColor.a, ColorMask[i] );
					}
				}
				
				SPatternOutput PatternOutput;
				PatternOutput._Diffuse 		= PatternColor;
				PatternOutput._Diffuse.a = Desc._UseOpacity ? PatternNormalSample.b : 1.0f; // Set alpha (normalmap blue channel)
				PatternOutput._Normal 		= UnpackDecalNormal( PatternNormalSample, PatternColor.a );
				PatternOutput._Properties 	= PatternProperties;

				OpacityMask = min( ( ColorMask[0] + ColorMask[1] + ColorMask[2] + ColorMask[3] ), 1 );
				return PatternOutput;
			}
			
			void ApplyVariationPatterns( in VS_OUTPUT_PDXMESHPORTRAIT Input, inout float4 Diffuse, inout float4 Properties, inout float3 NormalSample, in float4 SecondColorMask )
			{
				float4 Mask = PdxTex2D( PatternMask, Input.UV0 );
				float4 PatternDiffuse = float4( 1.0f, 1.0f, 1.0f, 1.0f );
				float3 PatternNormal = float3( 0.0f, 0.0f, 1.0f );
				float4 PatternProperties = Properties;
				PatternProperties.r = 1.0f;

				float RandomNumber = GetRandomNumber( Input.InstanceIndex );
				for( int i = 0; i < 4; ++i )
				{
					if( Mask[i] > 0.0f )
					{
						float OpacityMask = 0;
						SPatternOutput PatternOutput = ApplyPattern( Input.UV1, GetPatternDesc( Input.InstanceIndex, i ), RandomNumber, i, OpacityMask );

						PatternDiffuse = lerp( PatternDiffuse, PatternOutput._Diffuse, Mask[i] * OpacityMask);
						PatternNormal = lerp( PatternNormal, PatternOutput._Normal.rgb, Mask[i] * OpacityMask);
						PatternProperties = lerp( PatternProperties, PatternOutput._Properties, Mask[i] * OpacityMask);

					}
				}

				//Currently, we're only using 2 channels, leaving 2 channels available.
				#ifdef SECOND_COLOR_MASK
					float MaskOffset = 4.0f;
					for( int i = 0; i < 2; ++i )
					{
						if( SecondColorMask[i] > 0.0f )
						{
							float OpacityMask = 0;
							SPatternOutput PatternOutput = ApplyPattern( Input.UV1, GetSecondPatternDesc( Input.InstanceIndex, i ), RandomNumber, ( i + MaskOffset ), OpacityMask );

							PatternDiffuse = lerp( PatternDiffuse, PatternOutput._Diffuse, SecondColorMask[i] * OpacityMask);
							PatternNormal = lerp( PatternNormal, PatternOutput._Normal.rgb, SecondColorMask[i] * OpacityMask);
							PatternProperties = lerp( PatternProperties, PatternOutput._Properties, SecondColorMask[i] * OpacityMask);
						}
					}
				#endif
				
				Diffuse *= PatternDiffuse;
				Diffuse.rgb *= PatternProperties.rrr; // pattern AO
				
				NormalSample = normalize( OverlayNormal( NormalSample, PatternNormal ) );
				Properties = PatternProperties;
				
				//EK2
				#ifdef ATTACHEMENT_DECAY

				//Get the DecalData for the decal containing above colour in Mip6
				DecalData Data = GetDecalData(float3(1.0f,0.0f,0.0f), DIFFUSE_DECAL, DecalCount);

				//Set Weight to be the transperancy/strength of the above decal
				float Weight = Data._Weight;
				uint DiffuseIndex = Data._DiffuseIndex;

				//R - WET MASK
				//G - THICK DIRT MASK
				//B - RUST MASK
				//A - WORN FABRIC MASK
				float4 DiffuseDecayMask2x = PdxTex2D( DecalDiffuseArray, float3( float2(float(RandomNumber+Input.UV0.x*2.0f),float(RandomNumber+Input.UV0.y*2.0f)), DiffuseIndex ) );
				float4 DiffuseDecayMask3x = PdxTex2D( DecalDiffuseArray, float3( float2(float(RandomNumber+Input.UV0.x*3.0f),float(RandomNumber+Input.UV0.y*3.0f)), DiffuseIndex ) );


				//RUST
				float3 RustMask = float3(0.4f,0.2f,0.13f);
				RustMask = RustMask * (DiffuseDecayMask3x.bbb);
				RustMask = Overlay( Diffuse.rgb, RustMask,1.0f );

				float ClothMask = float(1.0f-Mask[0])*float(1.0f-Mask[1])*float(1.0f-Mask[2])*float(1.0f-Mask[3]);
				float RustRoughness = DiffuseDecayMask2x.b*DiffuseDecayMask3x.b;

				Diffuse.rgb = lerp(Diffuse.rgb,RustMask,smoothstep(DiffuseDecayMask2x.b,DiffuseDecayMask2x.b+0.2f,Weight*0.8f)*smoothstep(1.0f-float(PatternProperties.b*2.0f),1.0f-PatternProperties.b,0.8f)*ClothMask);
				Properties.a = lerp(Properties.a,1.0f,smoothstep(RustRoughness,RustRoughness+0.3f,Weight*0.4)*smoothstep(1.0f-float(PatternProperties.b*2.0f),1.0f-PatternProperties.b,0.8f)*ClothMask);

				//Worn out fabrics
				float FabricMask = saturate(0.6f-DiffuseDecayMask2x.a);

				Diffuse.rgb = lerp(Diffuse.rgb,PatternProperties.rrr*float3(1.0f,0.85f,0.7f),smoothstep(FabricMask,FabricMask+0.3f,(Weight*0.37f)*(1.0f-ClothMask)*0.7f));
				
				Properties.b = lerp(Properties.b,0.0f,smoothstep(FabricMask,FabricMask+0.3f,(Weight*0.4f)*(1.0f-ClothMask)));
				Properties.a = lerp(Properties.a,1.0f,smoothstep(FabricMask,FabricMask+0.3f,(Weight*0.4f)*(1.0f-ClothMask)));

				//Holes in fabrics
				float WearMask = abs(0.8f-DiffuseDecayMask2x.a);
				Diffuse.a = lerp(Diffuse.a,0.0f,step(WearMask,Weight*0.3f)*(1.0f-ClothMask));

				//Stains in fabric
				float StainMask = saturate(DiffuseDecayMask3x.r*5.0f);
				Diffuse.rgb = Multiply(Diffuse.rgb,float3(StainMask,StainMask,StainMask), clamp(Weight*2.0f,0.0f,1.0f));


				//Layers of dirt
				float DirtMask = clamp( NormalSample.b * NormalSample.b, 0, 1 );
				DirtMask = max(DirtMask,DiffuseDecayMask3x.g*1.5f);
				float3 DirtDiffuse = float3(0.2f,0.1f,0.06f);
				
				DirtDiffuse *= Diffuse.rgb;
				Diffuse.rgb = lerp(Diffuse.rgb,DirtDiffuse,smoothstep(DirtMask*0.5f,DirtMask*1.5f,clamp(Weight*1.6f,0.0f,1.0f)));

				#endif
				//EK2
			}

			void ApplyClothFresnel( in VS_OUTPUT_PDXMESHPORTRAIT Input, in float3 CameraPos, in float3 Normal, inout float3 Color )
			{
				float4 Mask = PdxTex2D( PatternMask, Input.UV0 );
				for( int i = 0; i < 4; ++i )
				{
					if( Mask[i] > 0.0f )
					{
						SPatternDesc Desc = GetPatternDesc( Input.InstanceIndex, i );
						float3 ViewVector = normalize( CameraPos - Input.WorldSpacePos );
						float VdotN = saturate( dot( Normal, ViewVector ) ) + 1e-5;
						float CottonLike = pow( 1 - VdotN, Desc._InnerExp ) * Desc._InnerScale;
						float SilkLike = pow( VdotN, Desc._RimExp ) * Desc._RimScale;
						float ClothFresnel = CottonLike + SilkLike;
						Color = Color * max( 0, ClothFresnel );
					}
				}
			}
		#endif
	]]
}
