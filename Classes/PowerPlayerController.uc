//==============================================================================
// PowerPlayerController
//
// handles cover system.  handles input.  handles sprinting.
//
// Contact : contact@whitemod.com
// Website : www.whitemod.com
// License : Content is available under Creative Commons Attribution-ShareAlike
//			 3.0 License.
//==============================================================================

class PowerPlayerController extends UTPlayerController;

`define Trace(obj) `obj.Run( self );

// have we pressed the cover button?
var	bool	TryingCover;
// are we actually taking cover?
var	bool	TakingCover;
// input related
var bool    ToggleCover;

// used for scaling the cover analysis complexity
var	float	LastDeltaTime;
var	float	AverageDeltaTime;
var bool    bReloading;

struct		SCoverConfig
{
	// bias' that are used for determining which wall to press against
	var float	ForwardBias;
	var float	BackBias;
	var float	LeftBias;
	var float	RightBias;

	var float	NormalErrorThreshold;
	var float	GoalErrorThreshold;

	var float	AnalysisInterval;

	// closeness of cover needed to enter cover state
	var float	MinProximity;

	//interval at which we bypass the cover checks for updating goals/normals
	var float	RefreshInterval;

	var float	MaxSideExposure;
	var int		AnalysisComplexity;

   // ideal distance we are from the wall
	var float	IdealDistance;

	// the amount to which the camera should be allowed to rotate while in cover
	var int		MaxCameraSwivel;

	structdefaultproperties
	{
		AnalysisInterval = 0.05

		ForwardBias				= 24.0
		BackBias				= 0.0
		LeftBias				= 16.0
		RightBias				= 16.0

		MaxSideExposure			= 96.0;

		NormalErrorThreshold	= 0.025
		GoalErrorThreshold		= 32

		IdealDistance			= 64.0
		MinProximity			= 64.0
		RefreshInterval			= 0.1
		AnalysisComplexity		= 32
		MaxCameraSwivel			= 19000
	}
};

var config	SCoverConfig	CoverConfig;

struct		SCoverWall
{
	// goal position we are covering on
	var vector	Goal;

	// surface normal of the covergoal
	var vector	Normal;

	// direction relative to player
	var int		Direction;

	// precedence this wall takes in becoming the goal wall
	var float	Bias;

	structdefaultproperties
	{
		Goal		= (X=0.0,Y=0.0,Z=0.0)
		Normal		= (X=0.0,Y=0.0,Z=0.0)
		Direction	= DIR_NONE
		Bias		= 1.0f
	}
};

struct		SCover
{
	var	SCoverWall		Wall;

	var vector			DirectionNormal;

	var float			LastAnalysis;

	//Cover Fire
	var float			Exposure;
	var float			LastExposure;
	// used for pausing the stacking state for a short period before exposure
	var float			ExposureTime;

	//time to refresh the cover normals!
	var	float			LastRefresh;

	// last time we went into cover
	var float			TimeCover;

	var	bool			Enabled;

	// last wall we switched
	var SCoverWall		LastWall;

	//uses ECoverDirection to specify where the wall was originally pressed on
	var int				CoveredFrom;

	//uses ECoverDirection to specify where the edge is
	var SCoverWall		Edge;

	structdefaultproperties
	{
		TimeCover			= 0.0f
		LastAnalysis		= 0.0f
		ExposureTime		= 0.0f
		LastRefresh			= 0.0f
		Enabled				= true
	}
};

var SCover	Cover;

var enum EDirection
{
	DIR_NONE,
	DIR_FORWARD,
	DIR_BACK,
	DIR_LEFT,
	DIR_RIGHT,
} CoverDirections;

/******************************************************************************/
/************************************ BODY ************************************/
/******************************************************************************/
/***
	Functions:
		EndCoverAnalysis			-
		CheckCoverAnalysisGoal		-
		CheckCoverAnalysisNormal	-
		CheckCoverExposure			-

		TryCoverWall				-
		TryCoverEdge				-
		ChooseCoverWall				-
		TryCover					- sees if we can cover in the first place
		BeginCover					- initiates cover
		EndCover					- ends cover state and cleans up variables
		ResetCoverVariables			- cleans up cover vars every tick

		GetPlayerViewPoint			- renders third person camera
		PlayerTick					- called every frame
		PreRender					- renders the HUD and PProcessing effects

	States:
		PlayerWalking				- handles sprinting toggle

		Sprinting					- the player is sprinting

		Covering					-	sticks players to the determined wall normal... may be able to
									override the regular cover methods with the AnalyzeCover method
									in order to preserve simplicity.

		Stacking					-	player is against an edge and can peak
***/

simulated event PostBeginPlay()
{
	Super.PostBeginPlay();
}

exec function ToggleCoverState()
{
	ToggleCover = !ToggleCover;
	TryingCover = ToggleCover;
	GetALocalPlayerController().ClientMessage("ToggleCover="$ToggleCover);
}

// does stuff with the input
simulated function CheckInput( float DeltaTime )
{
	if ( !Cover.Enabled )
	{
		//`log("Cover not enabled");
		EndCover();
	}
	else if ( Cover.LastAnalysis + CoverConfig.AnalysisInterval <= WorldInfo.TimeSeconds && !IsDead() && TryingCover )
	{
		if ( !IsInState( 'Stacking' ) )
		{
			//`log("Resetting cover variables");
			ResetCoverVariables();
		}

		if ( IsInState( 'Covering' ) )
		{
			//`log("Analyzing cover");
	   		AnalyzeCover( DeltaTime );
		}
	   	else
  	 	{
			//`log("Trying cover");
			TryCover();
		}

		if ( !IsZero( Cover.Wall.Goal ) )
		{
			//`log("Beginning cover");
			BeginCover();
		}
		else
		{
			//`log("Ending cover");
			EndCover();
		}

		Cover.LastAnalysis = WorldInfo.TimeSeconds;
	}
	else if ( Cover.LastAnalysis + CoverConfig.AnalysisInterval <= WorldInfo.TimeSeconds )
	{
		//`log("Unwanted ending cover");
		EndCover();
	}
}

/******************** UTILITY METHODS *******************/
// gets the direction normal based on the characters location
simulated function vector GetDirection( EDirection Direction, optional rotator RotationOffset = rot( 0,0,0 ) )
{
 	local rotator PawnRotation;
 	local vector x, y, z;

	PawnRotation = Pawn.Rotation;
	PawnRotation.Roll = 0;
	PawnRotation.Pitch = 0;

	GetAxes( PawnRotation + RotationOffset, x, y, z );

	switch ( Direction )
	{
		case DIR_FORWARD:
			return x;

		case DIR_BACK:
			return -1.0f * x;

		case DIR_LEFT:
			return -1.0f * y;

		case DIR_RIGHT:
			return y;

		default:
			return vect(0,0,0);
	}
}

/******************** COVER METHODS *******************/

// traces for potential wall candidates... if trace is successful, add to hitcount and analysis normal
simulated function AnalyzeCoverWall( float PercentComplete, rotator Offset, out int HitCount, out vector NewNormal )
{
	local PowerTrace WallTrace;
	//local SCoverConfig DefaultConfig;
	//local float Complexity;

	WallTrace =  new class'Power.PowerTrace';
	WallTrace.Start = Cover.Wall.Goal + Cover.Wall.Normal * CoverConfig.IdealDistance * ( PercentComplete * 2.9 + 0.1 );

	WallTrace.End = WallTrace.Start;
	WallTrace.End +=  vector(rotator(Cover.Wall.Normal * -1.0f) + Offset) * CoverConfig.MinProximity * ( PercentComplete * 1.5 + 1.0 );

	`Trace( WallTrace );

	if ( WallTrace.Hit() )
	{
		WallTrace.Normal.z = 0.0f;
		NewNormal += WallTrace.Normal;
		HitCount++;
	}
}

// do a full cover analysis
simulated function AnalyzeCover( float DeltaTime, optional int Step = 0, optional int HitCount = 0, optional vector NewNormal = vect(0,0,0) )
{
	local rotator Offset;
	local float PercentComplete;

	if ( Step == 0 )
		BeginCoverAnalysis( DeltaTime, NewNormal );

	if ( Step >= CoverConfig.AnalysisComplexity )
	{
		EndCoverAnalysis( HitCount, NewNormal, DeltaTime );
		return;
	}

	PercentComplete = ( float(Step) / float(CoverConfig.AnalysisComplexity) );

	//Offset = rot( 0, 12888, 0 );
	Offset = rot( 0, 8192, 0 );
	Offset.Yaw *= 1.0f - PercentComplete;

	if ( PlayerInput.aStrafe < 0 )
		Offset *= -1;

	//if we aren't moving, analyze both directions
	if ( PlayerInput.aStrafe == 0 )
	{
		AnalyzeCoverWall( PercentComplete, Offset, HitCount, NewNormal );
		AnalyzeCoverWall( PercentComplete, Offset * -1.0, HitCount, NewNormal );

		Step++;
	}
	else
		AnalyzeCoverWall( PercentComplete, Offset, HitCount, NewNormal );

	AnalyzeCover( DeltaTime, ++Step, HitCount, NewNormal );
}

// error checks the goal determined by the analysis
simulated function bool CheckCoverAnalysisGoal( vector NewGoal )
{
	return ( VSize( NewGoal - Cover.Wall.Goal ) < CoverConfig.GoalErrorThreshold );
}

// error checks the normal determined by the analysis
simulated function bool CheckCoverAnalysisNormal( vector NewNormal )
{
	return ( !IsZero( Cover.LastWall.Normal ) && ( VSize( NewNormal - Cover.LastWall.Normal ) < CoverConfig.NormalErrorThreshold ) );
}

// checks to see if we are exposing ourselves via peak
simulated function CheckCoverExposure()
{
	local SCoverWall DefaultWall, LastEdge, LeftEdge, RightEdge;

	// we don't want to snag a wall on the other side of the door
	//if ( Cover.Exposure > 0.1 )
	//	return;
	if ( IsInState( 'Stacking' ) && Cover.Exposure >= 0.00 )
		return;

	if ( IsInState( 'Stacking' ) && Cover.Edge.Direction != DIR_NONE )
		LastEdge = Cover.Edge;

	// this where players start stacking
	if ( PlayerInput.aStrafe > 0 )
		TryCoverEdge( Cover.Edge, DIR_LEFT );
	else if ( PlayerInput.aStrafe < 0 )
		TryCoverEdge( Cover.Edge, DIR_RIGHT );
	else
	{
		TryCoverEdge( LeftEdge, DIR_LEFT );
		TryCoverEdge( RightEdge, DIR_RIGHT );

		if ( LeftEdge.Direction != DIR_NONE )
			Cover.Edge = LeftEdge;
		else if ( RightEdge.Direction != DIR_NONE )
			Cover.Edge = RightEdge;

	}

	// if we will be stacking (edge dir is left/right),
	// make sure if we aren't stacking already we aren't switching in and out
	// of stacking real fast...
	//
	// if we are stacking already, make sure our edge direction is the same
	if	( Cover.Edge.Direction != DIR_NONE
			&&
				( ( !IsInState( 'Stacking' ) && Cover.ExposureTime - 0.8 > WorldInfo.TimeSeconds )
				|| ( IsInState( 'Stacking' ) && Cover.Edge.Direction != LastEdge.Direction && LastEdge.Direction != DIR_NONE ) )
		)
	{
		//`DebugMessage( IsInState( 'Stacking' ), `DLEVEL_HIGH, "Cover" );
		Cover.Edge = DefaultWall;
	}
}

simulated function bool CheckCoverAutoCrouch()
{
	local vector TraceStart, TraceEnd, TraceLocation, TraceNormal;
	local Actor TraceActor;
	local vector CoverNormalNoZ;

	if ( bDuck != 0 )
	{
		TraceStart = Pawn.Mesh.GetBoneLocation( 'b_Head' );
		TraceStart.z += ( Pawn.default.BaseEyeHeight - Pawn.default.CrouchHeight );
	}
	else
		TraceStart = Pawn.Mesh.GetBoneLocation( 'b_Head' );

	TraceEnd = TraceStart;
	CoverNormalNoZ = Cover.Wall.Normal;
	CoverNormalNoZ.z = 0.0f;
	TraceEnd += -1.0 * CoverNormalNoZ * CoverConfig.MinProximity;

	TraceActor = Trace( TraceLocation, TraceNormal, TraceEnd, TraceStart, true, vect(0.1,0.1,0.1) );

	if ( TraceActor == None || TraceLocation == TraceEnd )
	{
		return true;
	}

	return false;
}

// initialies cover analysis variables
simulated function BeginCoverAnalysis( float DeltaTime, out vector NewNormal )
{
	local SCoverConfig DefaultConfig;

	if ( DeltaTime > AverageDeltaTime )
		CoverConfig.AnalysisComplexity -= 2;
	else
		CoverConfig.AnalysisComplexity += 2;

	CoverConfig.AnalysisComplexity = Clamp( CoverConfig.AnalysisComplexity, DefaultConfig.AnalysisComplexity / 4.0, DefaultConfig.AnalysisComplexity );

	NewNormal = Cover.Wall.Normal;
}

// determines the final wall normal to cover against
simulated function EndCoverAnalysis( int HitCount, vector NewNormal, float DeltaTime )
{
	local PowerTrace CoverTrace;
	local SCoverWall DefaultWall;
	local bool		RefreshCover;

	if ( HitCount <= 0 )
	{
		if ( VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) > CoverConfig.MaxSideExposure * 1.5 )
			Cover.Wall = DefaultWall;

		return;
	}

	// Give the previous normal precedence so our transitions are somewhat smooth
	NewNormal = Normal( ( Normal( NewNormal / HitCount ) * 5.0 + Cover.Wall.Normal * 6.0 ) / 11.0 );

	CoverTrace = new class'PowerTrace';
	CoverTrace.Start = Pawn.Mesh.GetBoneLocation( 'b_Hips' );
	CoverTrace.End = CoverTrace.Start;
	CoverTrace.End += -1.0 * NewNormal * CoverConfig.MinProximity;

	`Trace( CoverTrace );

	CheckCoverExposure();

	if ( CoverTrace.Hit() && Cover.Exposure <= 0.00 )
	{
		if ( PlayerInput.aStrafe != 0.0f )
			Cover.LastRefresh += DeltaTime;

		// should we change our normal?
		// also make sure we aren't exposing... cover will screw up the normals by our
		// changing position while exposing
		if ( Cover.LastRefresh > CoverConfig.RefreshInterval )
		{
			Cover.LastRefresh = 0.0;
			RefreshCover = true;
		}

		if ( RefreshCover || !CheckCoverAnalysisNormal( NewNormal ) )
		{
			Cover.LastWall = Cover.Wall;
			Cover.Wall.Normal = NewNormal;
		}

		// should we change our goal?  we need to check this against whether or
		// not we are stacking...
		if ( RefreshCover || CheckCoverAnalysisGoal( CoverTrace.Location ) )
			Cover.Wall.Goal = CoverTrace.Location;
		/*
		if ( CheckCoverAutoCrouch() )
			bDuck = 1;
		else
			bDuck = 0;
		*/
	}
	else if ( VSize( Cover.Wall.Goal - CoverTrace.Start ) > CoverConfig.MaxSideExposure * 1.5 )
	{
		Cover.Wall = DefaultWall;
	}
}

// tries a wall to see if it is in cover proximity
simulated function TryCoverWall( out SCoverWall Wall, EDirection Direction, optional EDirection Offset = DIR_NONE, optional float Bias = 1.0f, optional vector TraceExtent = vect(1,1,1) )
{
	local vector TraceStart, TraceEnd, TraceLocation, TraceNormal;
	local Actor TraceActor;
	local SCoverWall DefaultWall;
	local float OffsetMultiplier, ProximityMultiplier;

	OffsetMultiplier = ( IsInState( 'Stacking' ) ) ? 1.0 : 1.25;
	ProximityMultiplier = ( Offset == DIR_NONE ) ? 1.0 : 1.5;

   	if ( !IsZero( GetDirection( Offset ) ) )
   	{
		TraceStart = Pawn.Mesh.GetBoneLocation( 'b_Hips' );
		TraceEnd = TraceStart;
		TraceEnd += GetDirection( Offset ) * CoverConfig.MinProximity * OffsetMultiplier;

		TraceActor = Trace( TraceLocation, TraceNormal, TraceEnd, TraceStart, true, TraceExtent );

		if ( TraceActor != None && TraceLocation != TraceEnd )
		{
			Wall.Goal = TraceLocation;
			Wall.Normal = TraceNormal;
			Wall.Direction = Direction;
			Wall.Bias = Bias;
			return;
		}
	}


	TraceStart = Pawn.Mesh.GetBoneLocation( 'b_Hips' ) + GetDirection( Offset ) * CoverConfig.MinProximity * OffsetMultiplier;
	TraceEnd = GetDirection( Direction ) * CoverConfig.MinProximity * ProximityMultiplier;

	TraceEnd += TraceStart;

	TraceActor = Trace( TraceLocation, TraceNormal, TraceEnd, TraceStart, true, TraceExtent );

	if ( TraceActor != None && TraceLocation != TraceEnd )
	{
		Wall.Goal = TraceLocation;
		Wall.Normal = TraceNormal;
		Wall.Direction = Direction;
		Wall.Bias = Bias;
		return;
	}

	Wall = DefaultWall;
}

// sees if there is an edge next to us
simulated function TryCoverEdge( out SCoverWall Wall, EDirection Direction )
{
	TryCoverWall( Wall, DIR_BACK, Direction,, vect( 1.0,1.0,1.0 ) );

	if ( IsZero( Wall.Goal ) )
		Wall.Direction = Direction;
	else
		Wall.Direction = DIR_NONE;
}

// chooses the initial wall to cover on
simulated function ChooseCoverWall( array<SCoverWall> CoverWalls )
{
	local int i;
	local SCoverWall DefaultWall;
	local SCoverWall ChosenWall;
	local bool NoZeroWall, ShortestDistance, PreferredWall;

	ChosenWall = DefaultWall;

	for ( i = 0; i < CoverWalls.length; i++ )
	{
		NoZeroWall = !IsZero( CoverWalls[i].Goal );
		ShortestDistance = VSize( CoverWalls[i].Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) < VSize( ChosenWall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) );
		PreferredWall = ( CoverWalls[i].Bias / ChosenWall.Bias  < VSize( CoverWalls[i].Goal - Pawn.Location ) / VSize( ChosenWall.Goal - Pawn.Location ) );

		if	( CoverWalls[i].Normal.z < 0.2 && NoZeroWall && ( ShortestDistance || PreferredWall ) )
			ChosenWall = CoverWalls[i];
	}

	Cover.LastWall = Cover.Wall;
	Cover.Wall = ChosenWall;
	Cover.TimeCover = WorldInfo.TimeSeconds;

	switch ( Cover.Wall.Direction )
	{
		case DIR_LEFT:
		case DIR_RIGHT:
  			`log( "Chosen Side Cover");
			break;
		case DIR_FORWARD:
  			`log( "Chosen Forward Cover");
			break;
		case DIR_BACK:
  			`log( "Chosen Behind Cover");
			break;
	}
}

// TryCover gathers appropriate wall data and determines
// which wall the user will press against.
simulated function TryCover()
{
	local array<SCoverWall> CoverWalls;

	TryCoverWall( CoverWalls[0], DIR_FORWARD,, CoverConfig.ForwardBias );
	TryCoverWall( CoverWalls[1], DIR_BACK,, CoverConfig.BackBias );
	TryCoverWall( CoverWalls[2], DIR_LEFT,, CoverConfig.LeftBias );
	TryCoverWall( CoverWalls[3], DIR_RIGHT,, CoverConfig.RightBias );

	ChooseCoverWall( CoverWalls );
}

simulated function BeginCover()
{
	TakingCover = true;

	if ( Cover.Edge.Direction != DIR_NONE && !IsInState( 'Stacking' ) )
		GotoState( 'Stacking' );
	else if ( Cover.Edge.Direction == DIR_NONE && ( !IsInState( 'Covering' ) || IsInState( 'Stacking' ) ) )
		GotoState( 'Covering' );
}

simulated function EndCover()
{
	ToggleCover = false;

	TakingCover = false;
	if ( IsInState( 'Covering' ) )
		GotoState( 'PlayerWalking' );
}

simulated function ResetCoverVariables()
{
	local SCoverWall DefaultWall;

	Cover.Edge = DefaultWall;
}

/******************** CAMERA STUFF *******************/
simulated event GetPlayerViewPoint( out vector POVLocation, out Rotator POVRotation )
{
	local float DeltaTime;

	// goto third person
	SetBehindView( true );

	DeltaTime = WorldInfo.TimeSeconds - LastCameraTimeStamp;

	if ( PlayerCamera == None )
	{
		SpawnPlayerCamera();
		SetViewTarget( PlayerCamera );
	}

	if ( PlayerCamera != None)
	{
		if ( Pawn != None )
			PlayerCamera.SetViewTarget( Pawn );

		PlayerCamera.UpdateCamera( DeltaTime );
		PlayerCamera.GetCameraViewPoint( POVLocation, POVRotation );
	}
	LastCameraTimeStamp = WorldInfo.TimeSeconds;
}

/******************** PLAYER UPDATE *******************/
// just gather input for now
event PlayerTick( float DeltaTime )
{
	CheckInput( DeltaTime );

	if ( AverageDeltaTime != 0.0 )
		AverageDeltaTime = ( AverageDeltaTime + DeltaTime ) / 2.0;
	else
		AverageDeltaTime = DeltaTime;

	super.PlayerTick( DeltaTime );

	PowerCamera(PlayerCamera).SetInputs( PlayerInput.aForward, PlayerInput.aStrafe, PlayerInput.aUp );
	LastDeltaTime = DeltaTime;
}

state PlayerWalking
{
	function ProcessMove(float DeltaTime, vector NewAccel, eDoubleClickDir DoubleClickMove, rotator DeltaRot)
	{
		if ( DoubleClickMove == DCLICK_Forward && !IsInState( 'Covering' ) )
			GotoState( 'Sprinting' );

		Super.ProcessMove( DeltaTime, NewAccel, DoubleClickMove, DeltaRot );
	}
}

/******************** SPRINTING *******************/
state Sprinting extends PlayerWalking
{
	function BeginState( name PreviousStateName )
	{
  		//`log( "Started Sprinting" );

		Super.BeginState( PreviousStateName );

		Pawn.GroundSpeed *= 1.95;
		PlayerCamera.GotoState( 'VeryLazy' );
	}

	function EndState( name NextStateName )
	{
		Pawn.GroundSpeed = Pawn.Default.GroundSpeed;
		PlayerCamera.GotoState( 'Lazy' );

		Super.EndState( NextStateName );

  		//`log( "Ended Sprinting" );
	}

	simulated function PlayerTick( float DeltaTime )
	{
		Global.PlayerTick( DeltaTime );

		if ( PlayerInput.aForward == 0.0 && IsInState( 'Sprinting' ) )
			GotoState( 'PlayerWalking' );
	}

Begin:
	Sleep( 0.2 ); // will stay in sprint for this duration after letting go of sprint key
}

/******************** COVER STATES *******************/
state Covering extends PlayerWalking
{
	function BeginState( name PreviousStateName )
	{
		local rotator CoverRotation;
  		//`log( "Started Cover");

		Super.BeginState( PreviousStateName );

		// goto third person
		SetBehindView( true );

		// don't allow us to move as fast...
		// TODO: do sidestepping effect so you move step by step...
		//		it would be a camera thing
		if ( Pawn != None )
			Pawn.GroundSpeed *= 0.8;

		// taken from the WPawn code because we weren't hitting the pawn tick
		// be the time we got to the next player controller tick
		//
		// make sure if we are covering we make the pawn face AWAY from the wall
		CoverRotation = Normalize( rotator(Normal( Cover.Wall.Normal ) ) );
		CoverRotation.Pitch = 0;
		Pawn.SetRotation( CoverRotation );
		if (CheckCoverAutoCrouch())
		{
			bDuck = 1;
		}
		PlayerCamera.GotoState( 'Covering' );
	}

	function EndState( name NextStateName )
	{
		if ( NextStateName != 'Stacking' )
			bDuck = 0;

		// undo all the stuff we did in beginstate
		SetBehindView( false );

		if ( Pawn != None )
			Pawn.GroundSpeed = Pawn.Default.GroundSpeed;

		Super.EndState( NextStateName );
		PlayerCamera.GotoState( 'Lazy' );

  		//`log( "Ended Cover" );
	}

	// most of the code here is copied from one of the base classes...
	function PlayerMove( float DeltaTime )
	{
		local vector			X,Y,Z, NewAccel;
		local eDoubleClickDir	DoubleClickMove;
		local rotator			OldRotation, HalfCircle, CoverBiNormal;

		if( Pawn == None )
		{
			GotoState('Dead');
			return;
		}

		GroundPitch = 0;

		// we calculate a rotator parallel to the surface
		HalfCircle = rot( 0, 16384, 0 );
		CoverBiNormal = Normalize( rotator(Cover.Wall.Normal) - HalfCircle );

		GetAxes(CoverBiNormal,X,Y,Z);

		// and update acceleration based on this parallel vector
		NewAccel = PlayerInput.aStrafe*X;

		NewAccel.Z	= 0;
		NewAccel = Pawn.AccelRate * Normal(NewAccel);

		// now we make sure we move a little bit towards the wall we are pressing on...
		// this is used for cylinders and such.
		NewAccel += Max( 0.25, ( VSize( NewAccel ) / Pawn.AccelRate ) ) * ( Pawn.AccelRate * ( VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) / CoverConfig.IdealDistance ) * -Y );
		DoubleClickMove = PlayerInput.CheckForDoubleClickMove( DeltaTime/WorldInfo.TimeDilation );

		// Update rotation.
		UpdateRotation( DeltaTime );
		bDoubleJump = false;

		if( bPressedJump )
		{
			bPressedJump = false;
		}

		if( Role < ROLE_Authority ) // then save this move and replicate it
			ReplicateMove(DeltaTime, NewAccel, DoubleClickMove, OldRotation - Rotation);
		else
			ProcessMove(DeltaTime, NewAccel, DoubleClickMove, OldRotation - Rotation);
	}

	simulated event GetPlayerViewPoint( out vector POVLocation, out Rotator POVRotation )
	{
		local float DeltaTime;
		local rotator CoverRotation, FinalRotation; // final rotation used for camera swivel

		DeltaTime = WorldInfo.TimeSeconds - LastCameraTimeStamp;

		if ( PlayerCamera == None )
		{
			SpawnPlayerCamera();
			Global.SetViewTarget( PlayerCamera );
		}

		if ( Pawn != None )
			SetViewTarget( Pawn );

		CoverRotation = Normalize( rotator(Normal( Cover.Wall.Normal * -1.0 ) ) );

		
		FinalRotation = Rotation;
		if ( CoverRotation.Yaw - Rotation.Yaw > CoverConfig.MaxCameraSwivel )
			FinalRotation.Yaw = CoverRotation.Yaw - CoverConfig.MaxCameraSwivel;
		else if ( CoverRotation.Yaw - Rotation.Yaw < -1.0f * CoverConfig.MaxCameraSwivel )
			FinalRotation.Yaw = CoverRotation.Yaw + CoverConfig.MaxCameraSwivel;
		else
			FinalRotation.Yaw = Rotation.Yaw;
		

		SetRotation( FinalRotation );

		PlayerCamera.UpdateCamera( DeltaTime );
  		PlayerCamera.GetCameraViewPoint( POVLocation, POVRotation );

		LastCameraTimeStamp = WorldInfo.TimeSeconds;
	}
}

state Stacking extends Covering
{
	function BeginState( name PreviousStateName )
	{
  		//`log( "Started Peeking" );
		Super.BeginState( PreviousStateName );

		PowerPawn(Pawn).GotoState( 'Stacking' );
		Cover.Exposure = 0;
		Cover.LastExposure = 0;

		Cover.ExposureTime = WorldInfo.TimeSeconds;

		PlayerCamera.GotoState( 'Aiming' );
	}

	function EndState( name NextStateName )
	{

		Cover.LastExposure = 0;
		Cover.Exposure = 0;
		PowerPawn(Pawn).GotoState( '' );

		if ( NextStateName != 'Covering' )
		{
			Super.EndState( NextStateName );
			PlayerCamera.GotoState( 'Lazy' );
		}
		else
			PlayerCamera.GotoState( 'Covering' );

  		//`log( "Ended Peaking");
	}

	// most of the code here is copied from one of the base classes...
	function PlayerMove( float DeltaTime )
	{
		local vector			X,Y,Z, NewAccel;
		local eDoubleClickDir	DoubleClickMove;
		local rotator			OldRotation, HalfCircle, CoverBiNormal;
		local float				Increment, AccelVel;

		if( Pawn == None )
		{
			GotoState('Dead');
			return;
		}

		GroundPitch = 0;

		// we calculate a rotator parallel to the surface
		HalfCircle = rot( 0, 16384, 0 );
		CoverBiNormal = Normalize( rotator(Cover.Wall.Normal) - HalfCircle );

		GetAxes(CoverBiNormal,X,Y,Z);

	   	Increment = DeltaTime;
	   	AccelVel = 16;

	   	// do the exposure anim in this if block
		if ( Cover.Exposure < 0.25f && Cover.Exposure > 0.000000f && Cover.LastExposure != Cover.Exposure )
		{
			if ( Cover.LastExposure < Cover.Exposure )
			{
				if ( Cover.Edge.Direction == DIR_LEFT )
					NewAccel = AccelVel * DeltaTime * X;
				else
					NewAccel = AccelVel * -1.0f * DeltaTime * X;

				Cover.Exposure += Increment;
			}
			else if ( Cover.LastExposure > Cover.Exposure )
			{
				if ( Cover.Edge.Direction == DIR_LEFT )
					NewAccel = AccelVel * -1.0f * DeltaTime * X;
				else
					NewAccel = AccelVel * DeltaTime * X;

				Cover.Exposure -= Increment;
			}

		}
		else if ( Cover.Edge.Direction == DIR_LEFT )
		{
			Cover.LastExposure = Cover.Exposure;

			if (  PlayerInput.aStrafe > 0 )
				Cover.Exposure += Increment;
			else if ( PlayerInput.aStrafe < 0 )
				Cover.Exposure -= Increment;

			if ( VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) < CoverConfig.MaxSideExposure || PlayerInput.aStrafe < 0 )
				NewAccel = AccelVel * PlayerInput.aStrafe * DeltaTime * X;
			else
				Cover.Exposure = 1.0;

			// seems like this is where the animation gets triggered :)
			// i think this was done to purposefully maintain the distance
			// between the peak start/end and the animation timing
			if ( PlayerInput.aStrafe < 0 && VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) < 64 && Cover.Exposure >= 0.25 )
			{
				NewAccel = vect(0,0,0);
				Cover.Exposure = 0.24;
			}
		}
		else if ( Cover.Edge.Direction == DIR_RIGHT )
		{
			Cover.LastExposure = Cover.Exposure;

			if (  PlayerInput.aStrafe < 0 )
				Cover.Exposure += Increment;
			else if (  PlayerInput.aStrafe > 0 )
				Cover.Exposure -= Increment;

			if ( VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) < CoverConfig.MaxSideExposure || PlayerInput.aStrafe > 0 )
				NewAccel = AccelVel * PlayerInput.aStrafe * DeltaTime * X;
			else
				Cover.Exposure = 1.0;

			if ( PlayerInput.aStrafe > 0 && VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) < 64 && Cover.Exposure >= 0.25 )
			{
				NewAccel = vect(0,0,0);
				Cover.Exposure = 0.24;
			}
		}

		Cover.Exposure = FClamp( Cover.Exposure, -0.200000f, 1.0f );

		// and update acceleration based on this parallel vector
		if ( Cover.Exposure < DeltaTime )
			NewAccel = Normal(PlayerInput.aStrafe*X);

		NewAccel.Z	= 0;
		NewAccel = Pawn.AccelRate * NewAccel;

		if ( Cover.Exposure <= DeltaTime && Cover.ExposureTime + 0.4 > WorldInfo.TimeSeconds )
		{
			NewAccel = vect(0,0,0);
			Cover.Exposure = 0.000000f;
		}
		else if ( Cover.Exposure > LastDeltaTime )
			Cover.ExposureTime = WorldInfo.TimeSeconds;

		// now we make sure we move a little bit towards the wall we are pressing on...
		// this is used for cylinders and such.
		//NewAccel += Max( 0.5, ( VSize( NewAccel ) / Pawn.AccelRate ) ) * ( Pawn.AccelRate * ( VSize( Cover.Wall.Goal - Pawn.Mesh.GetBoneLocation( 'b_Hips' ) ) / CoverConfig.IdealDistance ) * -Y );

		DoubleClickMove = PlayerInput.CheckForDoubleClickMove( DeltaTime/WorldInfo.TimeDilation );

		// Update rotation.
		UpdateRotation( DeltaTime );
		bDoubleJump = false;

		if( bPressedJump )
		{
			bPressedJump = false;
		}

		if( Role < ROLE_Authority ) // then save this move and replicate it
			ReplicateMove(DeltaTime, NewAccel, DoubleClickMove, OldRotation - Rotation);
		else
			ProcessMove(DeltaTime, NewAccel, DoubleClickMove, OldRotation - Rotation);
	}

	simulated event GetPlayerViewPoint( out vector POVLocation, out Rotator POVRotation )
	{
		super.GetPlayerViewPoint( POVLocation, POVRotation );
	}
}


defaultproperties
{
	ToggleCover = false;
	LastDeltaTime = 0.0
	AverageDeltaTime = 0.0

	CameraClass = Class'PowerCamera'
}
