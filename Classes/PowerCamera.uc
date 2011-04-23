//=============================================================================
// PowerCamera
//
// Renders the 3rd person camera in various modes.  Added camera bobbing.
//
// Contact : contact@whitemod.com
// Website : www.whitemod.com
// License : Content is available under Creative Commons Attribution-ShareAlike
//			 3.0 License.
//=============================================================================

class PowerCamera extends Camera;

var vector LazyLocation;
var rotator LazyRotation;
var int LocationLaziness, RotationLaziness;
var float AimLocationLaziness, AimRotationLaziness;
var float TransitionInterval;
var vector TransitionOffset;
var float CameraRoll;
var vector	CoverOffset;

var rotator RotationModifier;
var rotator MaxRotationModifier;
var float LastKickTime;

var float Forward, Strafe, Up;

var vector VeryLazyCamOffset, LazyCamOffset, AimCamOffset;

// Let's the camera know how the player is moving so it can simulate camera bobbing and similar stuff.
simulated function SetInputs(float InForward, float InStrafe, float InUp)
{
	Forward = InForward / 2000.0f;
	Strafe = InStrafe / 2000.0f;
	CoverOffset = FreeCamOffset; //used in else if statement below for modifying camera angles during cover
	Up = InUp;
}

// renders the third person camera location

function UpdateViewTarget(out TViewTarget OutVT, float DeltaTime)
{
	local vector VTLocation, VTLocationWithZ, DesiredLocation, TraceLocation, TraceNormal, x, y, z;
	local rotator Rot;
 	local Actor TraceActor;

	VTLocation = OutVT.Target.Location;

	VTLocationWithZ = VTLocation;
	VTLocationWithZ.z += FreeCamOffset.z;
	TraceActor = Trace( TraceLocation, TraceNormal, VTLocationWithZ, VTLocation, true, vect(8,8,8) );

	VTLocationWithZ = ( TraceActor == None ) ? VTLocationWithZ : TraceLocation;

	// take pitch from the player controller (pawn doesn't use pitch)
	Rot = PCOwner.Rotation + RotationModifier;
	//Rot.Yaw = OutVT.Target.Rotation.Yaw;

	//got rid of the roll on aiming mode... made for a rough camera
	if ( IsInState( 'Lazy' ) && !PCOwner.IsDead() && PowerPlayerController(PCOwner) != None && !PowerPlayerController(PCOwner).IsInState( 'Covering' ) )
	{
		if ( Strafe != 0.0 )
		{
			Rot.Roll = Strafe  * CameraRoll;
			Rot.Roll += Forward * sin( WorldInfo.TimeSeconds * 18 ) * CameraRoll * ( ( IsInState( 'VeryLazy' ) ) ? 0.15f : 0.075f );
		}
		else if ( Forward != 0.0 )
		{
			Rot.Roll = Forward * sin( WorldInfo.TimeSeconds * 18 ) * CameraRoll * ( ( IsInState( 'VeryLazy' ) ) ? 0.25f : 0.125f );
			Rot.Pitch += Forward * sin( WorldInfo.TimeSeconds * 18 ) * 512 * ( ( IsInState( 'VeryLazy' ) ) ? 0.25f : 0.125f ) + 256;
		}
	}
	if ( IsInState( 'Covering' ) && Strafe != 0.0f )
	{
		 CoverOffset.x = 128.0f * -1.0f;
		 CoverOffset.y = 24.0f;
		 if ( Strafe < 0.0f )
			Rot.Yaw -= 4576;
		else
			Rot.Yaw += 4576;
	}

	if ( IsInState( 'VeryLazy' ) )
		Rot.Roll *= 2.0;

	GetAxes( Normalize( Rot ), x, y, z );

	DesiredLocation = VTLocationWithZ;

	DesiredLocation.x += Normal(x).x * CoverOffset.x + Normal(y).x * CoverOffset.y;
	DesiredLocation.y += Normal(x).y * CoverOffset.x + Normal(y).y * CoverOffset.y;

	TraceActor = Trace( TraceLocation, TraceNormal, DesiredLocation, VTLocationWithZ, true, vect(16,16,16) );
	//hack: VLerp for no clippage
	OutVT.POV.Location = ( TraceActor == None ) ? DesiredLocation : VLerp( TraceLocation, VTLocationWithZ, 0.2 );
	OutVT.POV.Rotation = Rot;

	RotationModifier -= RotationModifier * ( RSize( RotationModifier ) / RSize( MaxRotationModifier ) ) + RotationModifier * ( WorldInfo.TimeSeconds - LastKickTime ) * 0.05;
}

simulated function Kick( int KickAmt )
{
	local rotator KickRot;

	KickRot.Pitch = KickAmt;
	KickRot.Yaw = KickAmt * 0.75 * FMax( 0.25, FRand() ) * (float(Rand( 2 )) - 1.0 );
	KickRot.Roll = KickAmt * 0.2 * FMax( 0.25, FRand() ) * (float(Rand( 2 )) - 1.0 );

	KickRot += RotationModifier;

	if ( KickRot.Pitch > MaxRotationModifier.Pitch )
		KickRot.Pitch = MaxRotationModifier.Pitch;
	if ( KickRot.Yaw > MaxRotationModifier.Yaw )
		KickRot.Yaw = MaxRotationModifier.Yaw;
	if ( KickRot.Roll > MaxRotationModifier.Roll )
		KickRot.Roll = MaxRotationModifier.Roll;

	RotationModifier = KickRot;

	LastKickTime = WorldInfo.TimeSeconds;
}

// default view... has some camera laziness
auto state Lazy
{
	event BeginState( name PreviousStateName )
	{
		FreeCamOffset = LazyCamOffset;
	}

	function UpdateViewTarget(out TViewTarget OutVT, float DeltaTime)
	{
		Global.UpdateViewTarget( OutVT, DeltaTime );

		// Do Location
		if ( IsZero( LazyLocation ) )
		{
			LazyLocation = PCOwner.ViewTarget.Location;
			LazyRotation = OutVT.POV.Rotation;
		}

		OutVT.POV.Location = ( LazyLocation * ( LocationLaziness - 1 ) + OutVT.POV.Location ) / LocationLaziness;

		// Do Rotation
		OutVT.POV.Rotation = Normalize( OutVT.POV.Rotation );
		OutVT.POV.Rotation.Pitch = Clamp( OutVT.POV.Rotation.Pitch, -16384, 16384 );

		if ( OutVT.POV.Rotation.Yaw - LazyRotation.Yaw > 32768 && LazyRotation.Yaw - OutVT.POV.Rotation.Yaw < 32768 )
			OutVT.POV.Rotation.Yaw -= 65536;
		else if ( LazyRotation.Yaw - OutVT.POV.Rotation.Yaw > 32768 && OutVT.POV.Rotation.Yaw - LazyRotation.Yaw < 32768 )
			OutVT.POV.Rotation.Yaw += 65536;

		if ( OutVT.POV.Rotation.Pitch - LazyRotation.Pitch > 32768 && LazyRotation.Pitch - OutVT.POV.Rotation.Pitch < 32768 )
			OutVT.POV.Rotation.Pitch -= 65536;
		else if ( LazyRotation.Pitch - OutVT.POV.Rotation.Pitch > 32768 && OutVT.POV.Rotation.Pitch - LazyRotation.Pitch < 32768 )
			OutVT.POV.Rotation.Pitch += 65536;

		OutVT.POV.Rotation = Normalize( ( LazyRotation * ( RotationLaziness - 1 ) + OutVT.POV.Rotation ) / RotationLaziness );

		// Store values
		LazyLocation = OutVT.POV.Location;
		LazyRotation = OutVT.POV.Rotation;
	}
}

state Covering extends Lazy
{
	event BeginState( name PreviousStateName )
	{
		FreeCamOffset = LazyCamOffset;
	}

	function UpdateViewTarget(out TViewTarget OutVT, float DeltaTime)
	{
		Global.UpdateViewTarget( OutVT, DeltaTime );

		// Do Location
		if ( IsZero( LazyLocation ) )
		{
			LazyLocation = PCOwner.ViewTarget.Location;
			LazyRotation = OutVT.POV.Rotation;
		}

		OutVT.POV.Location = ( LazyLocation * ( LocationLaziness * 1.25 - 1 ) + OutVT.POV.Location ) / ( LocationLaziness * 1.25 );

		// Do Rotation
		OutVT.POV.Rotation = Normalize( OutVT.POV.Rotation );
		OutVT.POV.Rotation.Pitch = Clamp( OutVT.POV.Rotation.Pitch, -16384, 16384 );

		if ( OutVT.POV.Rotation.Yaw - LazyRotation.Yaw > 32768 && LazyRotation.Yaw - OutVT.POV.Rotation.Yaw < 32768 )
			OutVT.POV.Rotation.Yaw -= 65536;
		else if ( LazyRotation.Yaw - OutVT.POV.Rotation.Yaw > 32768 && OutVT.POV.Rotation.Yaw - LazyRotation.Yaw < 32768 )
			OutVT.POV.Rotation.Yaw += 65536;

		if ( OutVT.POV.Rotation.Pitch - LazyRotation.Pitch > 32768 && LazyRotation.Pitch - OutVT.POV.Rotation.Pitch < 32768 )
			OutVT.POV.Rotation.Pitch -= 65536;
		else if ( LazyRotation.Pitch - OutVT.POV.Rotation.Pitch > 32768 && OutVT.POV.Rotation.Pitch - LazyRotation.Pitch < 32768 )
			OutVT.POV.Rotation.Pitch += 65536;

		OutVT.POV.Rotation = Normalize( ( LazyRotation * ( RotationLaziness * 1.25 - 1 ) + OutVT.POV.Rotation ) / ( RotationLaziness * 1.25 ) );

		// Store values
		LazyLocation = OutVT.POV.Location;
		LazyRotation = OutVT.POV.Rotation;
	}
}

// used for sprinting... has lots of laziness
state VeryLazy extends Lazy
{
	event BeginState( name PreviousStateName )
	{
		FreeCamOffset = VeryLazyCamOffset;
	}

	function UpdateViewTarget(out TViewTarget OutVT, float DeltaTime)
	{
		Global.UpdateViewTarget( OutVT, DeltaTime );

		// Do Location
		if ( IsZero( LazyLocation ) )
		{
			LazyLocation = PCOwner.ViewTarget.Location;
			LazyRotation = OutVT.POV.Rotation;
		}

		OutVT.POV.Location = ( LazyLocation * ( LocationLaziness * 1.5 - 1 ) + OutVT.POV.Location ) / ( LocationLaziness * 1.5 );

		// Do Rotation
		OutVT.POV.Rotation = Normalize( OutVT.POV.Rotation );
		OutVT.POV.Rotation.Pitch = Clamp( OutVT.POV.Rotation.Pitch, -16384, 16384 );

		if ( OutVT.POV.Rotation.Yaw - LazyRotation.Yaw > 32768 && LazyRotation.Yaw - OutVT.POV.Rotation.Yaw < 32768 )
			OutVT.POV.Rotation.Yaw -= 65536;
		else if ( LazyRotation.Yaw - OutVT.POV.Rotation.Yaw > 32768 && OutVT.POV.Rotation.Yaw - LazyRotation.Yaw < 32768 )
			OutVT.POV.Rotation.Yaw += 65536;

		if ( OutVT.POV.Rotation.Pitch - LazyRotation.Pitch > 32768 && LazyRotation.Pitch - OutVT.POV.Rotation.Pitch < 32768 )
			OutVT.POV.Rotation.Pitch -= 65536;
		else if ( LazyRotation.Pitch - OutVT.POV.Rotation.Pitch > 32768 && OutVT.POV.Rotation.Pitch - LazyRotation.Pitch < 32768 )
			OutVT.POV.Rotation.Pitch += 65536;

		OutVT.POV.Rotation = Normalize( ( LazyRotation * ( RotationLaziness * 1.5 - 1 ) + OutVT.POV.Rotation ) / ( RotationLaziness * 1.5 ) );

		// Store values
		LazyLocation = OutVT.POV.Location;
		LazyRotation = OutVT.POV.Rotation;
	}
}

// tight camera used for covering and such and peaking around walls
state Aiming extends Lazy
{
	// reset our transition values
	event BeginState( name PreviousStateName )
	{
		AimLocationLaziness = LocationLaziness;
		AimRotationLaziness = RotationLaziness;

		TransitionOffset = FreeCamOffset;

		// set the aim to be on the side that we are peaking...
		if ( AimCamOffset.y < 0 && PowerPlayerController(PCOwner).Cover.Edge.Direction == DIR_LEFT )
			AimCamOffset.y *= -1.0f;
		else if ( AimCamOffset.y > 0 && PowerPlayerController(PCOwner).Cover.Edge.Direction == DIR_RIGHT )
			AimCamOffset.y *= -1.0f;
	}

	function UpdateViewTarget(out TViewTarget OutVT, float DeltaTime)
	{
		Global.UpdateViewTarget( OutVT, DeltaTime );

		if ( AimLocationLaziness - TransitionInterval >= 1.0f  )
		{
			AimLocationLaziness -= TransitionInterval;

			if ( !IsZero( LazyLocation ) )
				OutVT.POV.Location = ( LazyLocation * ( LocationLaziness - 1 - ( LocationLaziness - AimLocationLaziness ) ) + OutVT.POV.Location * ( LocationLaziness - AimLocationLaziness + 1 ) ) / LocationLaziness;
		}

		if ( AimRotationLaziness - TransitionInterval >= 1.0f )
		{
			AimRotationLaziness -= TransitionInterval;

			// Do Rotation
			OutVT.POV.Rotation = Normalize( OutVT.POV.Rotation );
			OutVT.POV.Rotation.Pitch = Clamp( OutVT.POV.Rotation.Pitch, -16384, 16384 );

			if ( OutVT.POV.Rotation.Yaw - LazyRotation.Yaw > 32768 && LazyRotation.Yaw - OutVT.POV.Rotation.Yaw < 32768 )
				OutVT.POV.Rotation.Yaw -= 65536;
			else if ( LazyRotation.Yaw - OutVT.POV.Rotation.Yaw > 32768 && OutVT.POV.Rotation.Yaw - LazyRotation.Yaw < 32768 )
				OutVT.POV.Rotation.Yaw += 65536;

			OutVT.POV.Rotation = Normalize( ( ( LazyRotation * ( RotationLaziness - 1 - ( RotationLaziness - AimRotationLaziness ) ) ) + OutVT.POV.Rotation * ( RotationLaziness - AimRotationLaziness + 1 ) ) / RotationLaziness );
		}

		FreeCamOffset = VLerp( AimCamOffset, LazyCamOffset, ( AimLocationLaziness - 1.0f ) / float(LocationLaziness) );

		LazyLocation = OutVT.POV.Location;
		LazyRotation = OutVT.POV.Rotation;
	}
}

defaultproperties
{
	LazyLocation = (X=0,Y=0,Z=0)
	RotationModifier = (Pitch=0,Yaw=0,Roll=0)
	CameraStyle = 'ThirdPerson'
	VeryLazyCamOffset=(X=-192.0,Y=0.0,Z=80.0)
	LazyCamOffset=(X=-82.0,Y=20.0,Z=64.0)
	AimCamOffset=(X=-48.0,Y=32.0,Z=48.0)
	LocationLaziness=10
	RotationLaziness=8
	TransitionInterval=0.2
	CameraRoll=384.0
	MaxRotationModifier=(Pitch=16384,Yaw=2048,Roll=512)
}                    