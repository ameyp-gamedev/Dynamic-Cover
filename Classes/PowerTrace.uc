//==============================================================================
// PowerTrace
//
//	trace utility file
//
// Contact : contact@whitemod.com
// Website : www.whitemod.com
// License : Content is available under Creative Commons Attribution-ShareAlike
//			 3.0 License.
//==============================================================================

class PowerTrace extends Object;

var vector Start;
var vector End;
var vector Location;
var vector Normal;
var vector Extent;
var bool TraceActors;
var Actor Actor;
var TraceHitInfo HitInfo;

/*
const TRACEFLAG_Bullet			= 1;
const TRACEFLAG_PhysicsVolumes	= 2;
const TRACEFLAG_SkipMovers		= 4;
const TRACEFLAG_Blocking		= 8;
*/

simulated function Run( Object A )
{
	// TODO: maybe put in flags into the trace... MAYBE
	if ( Actor(A) != None )
		Actor = Actor(A).Trace( Location, Normal, End, Start, TraceActors, Extent, HitInfo );
}

simulated function bool HitActor()
{
	return ( Actor != None );
}

simulated function bool HitEnd()
{
	return ( Location == End );
}

simulated function bool Hit()
{
	return ( Actor != None || !HitEnd() );
}

simulated function float Size()
{
	return VSize( Location - Start );
}

defaultproperties
{
	Actor = None
	TraceActors = true
	Start = (X=0.000000,Y=0.000000,Z=0.000000)
	End = (X=0.000000,Y=0.000000,Z=0.000000)
	Location = (X=0.000000,Y=0.000000,Z=0.000000)
	Normal = (X=0.000000,Y=0.000000,Z=0.000000)
	Extent = (X=1.000000,Y=1.000000,Z=1.000000)
}
