//==============================================================================
// PowerPawn
//
// Complements the cover system by rotating the Pawn(player model).
//
// Contact : contact@whitemod.com
// Website : www.whitemod.com
// License : Content is available under Creative Commons Attribution-ShareAlike
//			 3.0 License.
//==============================================================================

class PowerPawn extends UTPawn;

var SkelControlSingleBone	SpineControl;

simulated event PostBeginPlay()
{
	Super.PostBeginPlay();
	//DetachComponent( ArmsMesh[0] );
	SetWeaponAttachmentVisibility( true );
}

// used for maintaining weapon visibility in 3rd person
simulated function SwitchWeapon(byte NewGroup)
{
	SetWeaponAttachmentVisibility( true );

	Super.SwitchWeapon( NewGroup );

	SetWeaponAttachmentVisibility( true );
}

simulated function Tick(float DeltaTime)
{
	local rotator CoverNormal;

	Super.Tick( DeltaTime );

	// make sure if we are covering we make the pawn face AWAY from the wall
	if ( Controller != None && Controller.IsInState( 'Covering' ) )
	{
		CoverNormal = Normalize( rotator(PowerPlayerController(Controller).Cover.Wall.Normal) );
		CoverNormal.Pitch = 0;
		SetRotation( CoverNormal );
	}
}

// aims our gun for us while in cover
simulated singular function Rotator GetBaseAimRotation()
{
	local rotator	POVRot;

	// If we have no controller, we simply use our rotation
	POVRot = Rotation;

	if ( Controller != None )
		POVRot.Pitch = Controller.Rotation.Pitch;

	//if ( IsInState( 'Stacking' ) )
		//POVRot.Yaw += WPlayerController(Controller).Cover.Exposure * SpineControl.BoneRotation.Roll;

	// If our Pitch is 0, then use RemoveViewPitch
	if( POVRot.Pitch == 0 )
	{
		POVRot.Pitch = RemoteViewPitch << 8;
	}

	return POVRot;
}

// controls rotation of the player while peeking.
state Stacking
{
	function BeginState( name PreviousStateName )
	{
		/* ameyp
		 * This doesn't work because I don't have a skeletal mesh with a SkelControl/Bone named SpineControl
		 * If you want it to work, you have to make your own Skeletal mesh for the player pawn
		 * and then uncomment the below lines and the commented lines in Defaultproperties
		*/

		/*
		SpineControl = SkelControlSingleBone( Mesh.FindSkelControl( 'SpineControl' ) );

		if ( PowerPlayerController(Controller).Cover.Edge.Direction == DIR_LEFT )
			SpineControl.BoneRotation.Roll = Abs( SpineControl.BoneRotation.Roll );
		else
			SpineControl.BoneRotation.Roll = -1.0 * Abs( SpineControl.BoneRotation.Roll );
		*/
	}

	function EndState( name NextStateName )
	{
		/* ameyp
		 * See the comments in BeginState
		 */

		//SpineControl.SetSkelControlStrength( 0.0, 0.2 );
	}


	simulated function Tick(float DeltaTime)
	{
		local rotator NewNormal, ControllerRot, From, To, CoverNormal, CoverNormalInverted;
		local float Exposure;
		local PowerPlayerController PPC;

		if (Controller == none)
			return;

		PPC = PowerPlayerController(Controller);

		Global.Tick( DeltaTime );

		Exposure = FClamp( PPC.Cover.Exposure, 0.0, 1.0 );

		//SpineControl.SetSkelControlStrength( Exposure, DeltaTime * 3.0f );

		CoverNormal = Normalize( rotator(PPC.Cover.Wall.Normal) );
		CoverNormalInverted = Normalize( rotator(PPC.Cover.Wall.Normal * -1.0f) );

		if ( PPC.Cover.Edge.Direction == DIR_LEFT )
			CoverNormalInverted.Yaw += 10.0;
		else if ( PPC.Cover.Edge.Direction == DIR_RIGHT )
			CoverNormalInverted.Yaw -= 10.0;

		Exposure *= 4.0f;

		From = rot(0,0,0);
		From.Yaw = CoverNormal.Yaw;

		To = rot(0,0,0);
		To.Yaw = CoverNormalInverted.Yaw;

		NewNormal.Pitch = 0;
		NewNormal.Yaw = RLerp( From, To, Exposure, true ).Yaw;
		NewNormal.Roll = 0;

		ControllerRot = Controller.Rotation;
		ControllerRot.Pitch = 0;


		if ( Exposure >= 1.0f )
		{
			SetRotation( ControllerRot );
			if ( PPC != None )
				PowerCamera(PPC.PlayerCamera).AimCamOffset.y = 0.0f;
		}
		else if ( Exposure >= 0.5f )
		{
			SetRotation( ( Normalize( NewNormal ) * 7.0f + ControllerRot ) / 8.0f );
			if ( PPC != None )
				PowerCamera(PPC.PlayerCamera).AimCamOffset.y = ( PowerCamera(PPC.PlayerCamera).AimCamOffset.y * 7.0 ) / 8.0;
		}
		else
		{
			SetRotation( Normalize( NewNormal ) );
			if ( PPC != None )
			{
				if ( PowerCamera(PPC.PlayerCamera).AimCamOffset.y < 0.0f )
					PowerCamera(PPC.PlayerCamera).AimCamOffset.y = -1.0f * PowerCamera(PPC.PlayerCamera).default.AimCamOffset.y;
				else
					PowerCamera(PPC.PlayerCamera).AimCamOffset.y = PowerCamera(PPC.PlayerCamera).default.AimCamOffset.y;
			}
		}
	}
}

defaultproperties
{
	GroundSpeed = 250.0
	HealthMax = 200
	Health = 200

	/*
	 * ameyp
	 * If you want the player to peek properly at corners, you'll have to make a skeletal mesh for the player pawn
	 * and add the appropriate animations, and then uncomment the lines below
	 */

	/*
	Begin Object Class=SkeletalMeshComponent Name=WhitePawnSkeletalMeshComponent ObjName=WhitePawnSkeletalMeshComponent
		AnimTreeTemplate=AnimTree'White_Animations.AT_CH_Human'
		MinDistFactorForKinematicUpdate=0.200000
		bUpdateSkelWhenNotRendered=False
		bIgnoreControllersWhenNotRendered=True
		bHasPhysicsAssetInstance=True
		bEnableFullAnimWeightBodies=True
		bOverrideAttachmentOwnerVisibility=True
		bChartDistanceFactor=True
		bCacheAnimSequenceNodes=False
		LightEnvironment=MyLightEnvironment
		bOwnerNoSee=True
		bUseAsOccluder=False
		BlockRigidBody=True
		RBChannel=RBCC_Untitled3
		RBCollideWithChannels=(Untitled3=True)
		RBDominanceGroup=20
		Translation=(X=0.000000,Y=0.000000,Z=8.000000)
		Scale=1.075000
		Name="WhitePawnSkeletalMeshComponent"
	End Object

	Mesh = WhitePawnSkeletalMeshComponent
	Components(3) = WhitePawnSkeletalMeshComponent
	*/
}
