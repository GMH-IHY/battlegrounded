--!strict
-- MovementConfig (ModuleScript)
-- Location: ReplicatedStorage > Movement > MovementConfig
--
-- Every movement number lives here so you can tune the feel without touching code.
-- Speeds are in studs per second. Times are in seconds.
-- For reference, Roblox's default WalkSpeed is 16 and default jump height is 7.2.

local MovementConfig = {
	-- WALKING ---------------------------------------------------------------
	-- You go straight to this speed when you start moving (no slow start).
	WalkSpeed = 14,

	-- RUNNING ---------------------------------------------------------------
	-- Double-tap W to run. Running stops when W is released.
	RunSpeed = 26,
	-- How long it takes to go from walk speed to full run speed. Keep it short:
	-- it's only there so the speed-up feels smooth.
	RunAccelTime = 0.22,
	-- How long it takes to drop from run speed back to walk speed.
	RunDecelTime = 0.12,
	-- Max gap between the two W taps.
	DoubleTapWindow = 0.3,

	-- LOW HEALTH -------------------------------------------------------------
	-- You walk and run slower as your health drops (JJS-style). Speed scales in a straight line
	-- from full speed at HealthSpeedFullAbove (share of max health) down to LowHealthSpeedScale
	-- at 0 health. With the defaults: 100% HP -> walk 14 / run 26, 50% -> 11.9 / 22.1,
	-- 10% -> 10.2 / 18.9. Air steering speed and the speed a dash hands back scale the same way,
	-- so jumping or dashing never gets around it. Momentum from a dash, wall hop or landing roll
	-- is NOT scaled: it bleeds off to the slower speed as usual.
	HealthSpeedFullAbove = 1,
	LowHealthSpeedScale = 0.7,

	-- MOMENTUM --------------------------------------------------------------
	-- If something pushes you ABOVE run speed (a dash, a launch, a long fall landing),
	-- the extra speed bleeds off at this rate (studs/s per second) instead of vanishing.
	MomentumDecay = 30,
	-- Turning sharper than this (degrees) while running costs you some speed.
	SharpTurnAngle = 110,
	-- Share of the speed above walk speed that you keep after a sharp turn (0 to 1).
	SharpTurnKeep = 0.4,

	-- JUMPING ---------------------------------------------------------------
	JumpHeight = 7.2,
	-- Grace period after walking off a ledge where a jump still works.
	CoyoteTime = 0.1,
	-- A jump pressed this long before landing still fires on landing.
	JumpBufferTime = 0.12,
	-- Let go of Space early to cut the jump short. Off by default because classic
	-- Roblox jumps are always the same height.
	VariableJumpHeight = false,
	-- Extra gravity while rising after Space is released (only if the option above is on).
	JumpCutGravityMultiplier = 2.5,

	-- TRUSSES / LADDERS -------------------------------------------------------
	-- Climbing speed (studs/s), the same however you got on: walking, sprinting, or grabbing it
	-- mid-air. Scales with health like walking and running.
	TrussClimbSpeed = 12,
	-- Jumping off a truss: it can't be grabbed again until this long after the jump AND you're
	-- falling, so jump-spamming never climbs faster than climbing (seconds).
	TrussRegrabDelay = 0.6,
	-- Grabbing a truss / ladder needs your keys pointing into it, this close (studs past the body).
	-- It never grabs while a dash, wall run, parkour move or landing roll is going.
	TrussGrabReach = 1.5,

	-- JUMP BUFFER AFTER MOVES -------------------------------------------------
	-- Space pressed during the last MoveJumpBuffer seconds of a dash, vault, step-up, climb or
	-- slide jumps the moment it ends (instead of being ignored). If the move ends in the air
	-- (a vault's drop, an air dash), the jump fires on landing within MoveJumpLandWindow.
	MoveJumpBuffer = 0.25,
	MoveJumpLandWindow = 0.4,

	-- AIR CONTROL -----------------------------------------------------------
	-- How quickly you can steer in the air (studs/s per second). Lower = more committed
	-- jumps, higher = floatier control. Classic Roblox is effectively infinite.
	AirAcceleration = 60,
	-- You keep your take-off speed in the air, but can always steer up to at least this.
	AirMinSpeed = 14,
	-- Horizontal slowdown in the air when you're not holding a direction.
	AirDrag = 6,
	-- Speed ABOVE run speed (from a dash-jump, wall hop, roll, slide...) bleeds off at this rate in
	-- the air (studs/s per second): momentum carries through jumps without lasting forever.
	-- On the ground MomentumDecay does the same, faster.
	AirMomentumDecay = 6,

	-- FALLING ---------------------------------------------------------------
	-- Gravity multiplier while falling. It ramps from 1 up to FallGravityMax over
	-- FallGravityRampTime, so the longer you fall, the faster you speed up.
	-- Rising is left at normal gravity, so your jump height stays at JumpHeight.
	FallGravityMax = 1.7,
	FallGravityRampTime = 0.35,
	-- Fastest you can fall (studs/s). Workspace gravity is 196.2 by default.
	TerminalVelocity = 120,

	-- BODY ------------------------------------------------------------------
	-- R6 legs don't collide, so an invisible box fills the leg area. It starts this far above
	-- the feet: bumps lower than this are stepped over (1.1 lets you walk up classic 1-stud
	-- steps), anything taller blocks you.
	-- The highest ledge you can jump onto is roughly JumpHeight + LowerColliderGap (about 8.3).
	LowerColliderGap = 1.1,
	-- How far the leg box sticks out past the torso on each side (studs). Keeps you from
	-- being popped up onto the edge of ledges you can't reach.
	LowerColliderMargin = 0.3,

	-- DASH (Shift) ------------------------------------------------------------
	-- The direction comes from the keys you hold, relative to the camera:
	--   no keys or W (W+A / W+D count too) -> front dash: long, and M1 during it throws the dash punch.
	--   A, D or S                          -> side / back quick-step: short.
	-- Both follow the camera while they travel, so you can curve them by turning.
	-- One dash, then a cooldown (JJS-style, a little shorter than JJS's).
	DashCooldown = 1.8,
	-- Front dash.
	FrontDashDistance = 25,
	FrontDashTime = 0.45,
	-- Side and back quick-steps.
	SideDashDistance = 17.5,
	SideDashTime = 0.36,
	-- Speed each dash eases down to by its end, if you're still holding a direction
	-- (the motor then carries it on). With no keys held the dash ends at a stop.
	DashEndSpeedWalking = 14,
	DashEndSpeedRunning = 26,
	-- Holding W when a dash ends starts a run (no double-tap needed).
	RunAfterDash = true,
	-- DASH-JUMP: Space at ANY point of a dash ends it and jumps with the dash's current speed
	-- (capped at MomentumMaxSpeed). Off the ground it still works if the dash touched the ground
	-- within DashJumpCoyote (dashed off a ledge); in a pure air dash the press jumps the moment
	-- the dash touches down. Front dashes that run into something vaultable / climbable /
	-- slide-able hand over to auto parkour at dash speed.
	DashJumpMinTime = 0,
	DashJumpCoyote = 0.15,
	-- Dashing in the air is allowed once per airtime.
	AirDashes = 1,
	-- Invincibility at the very start of a dash (for when combat exists). 4 frames at 60 fps.
	DashIFrames = 4 / 60,

	-- DASH PUNCH (M1 during a front dash) -------------------------------------
	-- You keep sliding while winding up the jab, then the fist lands. Heavy endlag after.
	DashPunchWindup = 0.16, -- from M1 to the hit
	DashPunchActive = 0.1, -- how long the hitbox stays out
	DashPunchEndlag = 0.55, -- stuck in place after the hitbox ends
	DashPunchBlockedEndlag = 0.3, -- extra endlag when the punch is blocked (once blocking exists)
	-- The slide carries on through the wind-up and slows to a stop by the hit. The punch
	-- always covers at least this far (so a punch thrown at the very end still lunges).
	DashPunchMinLunge = 5,
	DashPunchDamage = 4,
	-- Hitbox in front of the torso (studs): width, height, depth.
	DashPunchHitbox = Vector3.new(5, 5, 5),
	-- The punch ragdolls instead of stunning if it lands before the dash has traveled this
	-- share of FrontDashDistance.
	DashPunchRagdollShare = 0.5,

	-- WALL HOP ----------------------------------------------------------------
	-- Jump, then in the air next to a wall either keep HOLDING Space or PRESS it again, while your
	-- input points INTO the wall AND ALONG it (W+D / W+A toward the wall, like JJS): you run along
	-- the wall the way your input points, then kick off it. Just jumping into a wall, running
	-- parallel to it, or running straight into it doesn't hop.
	-- Zig-zag in an alley: at wall 1 hold W+D, then switch to W+A (away from it, toward wall 2)
	-- and you leap across with a big push; keep Space held (or press it) to hop wall 2.
	-- Hops per airtime by health: above 66% -> 3, above 33% -> 2, otherwise 1.
	WallHopsHigh = 3,
	WallHopsMid = 2,
	WallHopsLow = 1,
	-- How far from the wall (studs, from the body's edge) a hop can start.
	WallHopReach = 2,
	-- Space must be HELD since the jump, or PRESSED again while airborne (the jump's own press
	-- doesn't count). An airborne press this recent still hops when you reach the wall (seconds).
	WallHopPressBuffer = 0.32,
	-- Holding Space counts once it's been held this long (a quick tap isn't a hold) (seconds).
	WallHopHoldTime = 0.15,
	-- A wall you just left can still be hopped for this long (seconds).
	WallHopCoyote = 0.16,
	-- How much of your input must point into the wall, and along it (0..1). W+D at a wall
	-- 45 degrees off gives 0.71 of each; 0.3 accepts roughly 17-73 degrees from straight in.
	WallHopIntoMin = 0.3,
	WallHopAlongMin = 0.3,
	-- The keys themselves (relative to the camera) must include a forward key AND a side key:
	-- W+D / W+A. How much of each the input needs (0..1). W alone or D alone never hops.
	WallHopKeyMin = 0.3,
	-- The wall must still be there this far ahead in the run direction (studs).
	WallHopAheadCheck = 3,
	-- Clear space needed above the head to start a wall run (studs above the root).
	WallHopHeadroom = 4,
	-- Run along the wall before kicking off.
	WallRunTime = 0.22,
	WallRunSpeed = 24, -- along the wall (arrive faster and you keep it, up to WallRunMaxSpeed)
	WallRunMaxSpeed = 40,
	WallRunRise = 17.5, -- upward, studs/s
	-- The kick off the wall.
	WallHopHeight = 7.5, -- studs gained by the hop's arc
	-- Push straight away from the wall, by where your keys point as you leave it:
	WallHopPushInto = 7, -- still pointing into the wall (climb the same wall)
	WallHopPush = 13, -- pointing along it
	WallHopPushAway = 28, -- pointing away (zig-zag across to the other wall)
	-- Pointing this much away from the wall mid-run leaps off right away (0..1).
	WallHopLeapAway = 0.35,
	-- Turning your keys away within this long AFTER the kick still gets the big push (seconds).
	WallHopLateLeap = 0.18,
	WallHopCarry = 20, -- along the wall, the way you were running (or 85% of a faster run)
	-- After a kick: another wall can be grabbed after WallHopRegrabOther, the same wall after
	-- WallHopRegrab.
	WallHopRegrab = 0.28,
	WallHopRegrabOther = 0.1,
	-- Characters at least this many times normal size hop faster and farther, by their size.
	WallHopScaleFrom = 1.5,

	-- LANDING ROLL -------------------------------------------------------------
	-- Fall from higher than a jump and press Space right before landing to roll forward.
	-- The roll keeps the speed you landed with and adds distance that grows with the fall.
	-- Only falls at least this high (studs, from the airtime's highest point) can roll. A bit more
	-- than JumpHeight, so a normal jump on flat ground never rolls.
	LandingRollMinFall = 8.2,
	-- The press must be at most this long before touching down (seconds). Earlier = no roll.
	LandingRollWindow = 0.28,
	LandingRollTime = 0.45,
	-- Extra distance: base + per stud fallen above LandingRollMinFall, capped.
	LandingRollBaseDistance = 6,
	LandingRollDistancePerStud = 0.3,
	LandingRollMaxBonus = 16,
	-- A fresh Space press this close to the end of a roll jumps right out of it (seconds).
	LandingRollJumpBuffer = 0.2,
	-- Share of the landing speed kept when you roll straight back against your momentum (full
	-- speed up to 45 degrees off it, sliding linearly down to this at 180).
	LandingRollTurnKeep = 0.7,

	-- AUTO PARKOUR ------------------------------------------------------------
	-- Sprint into an obstacle and you vault it, step up onto it, climb it or slide under it
	-- automatically. Heights are measured from your feet. See AutoParkour.
	-- Your keys must point at the obstacle within this many degrees of head-on. Vaults and
	-- step-ups go the way you're running when that line works (straight over otherwise);
	-- climbs go straight up the face.
	ParkourMaxAngle = 55,
	-- CORNERS: coming in steeper than that (up to this many degrees), a face that ENDS within
	-- ParkourCornerZone studs ahead of you is a corner you're clipping: you go over the corner
	-- the way your keys point instead of sliding off it. Brushing along the middle of a face
	-- still does nothing.
	ParkourCornerMaxAngle = 82,
	ParkourCornerZone = 2.2,
	-- On the ground you must be moving at least this share of your run speed, OR be pressed up
	-- against the obstacle (it stopped you, or you started right next to it).
	ParkourMinSpeedShare = 0.5,
	-- How far ahead it looks: 0.6 studs + your speed times this (seconds), at least ParkourLookMin.
	ParkourLookTime = 0.14,
	ParkourLookMin = 2.0,
	-- Pause after one action before another can start (seconds).
	ParkourCooldown = 0.1,
	-- After a move got blocked, wait this long before trying again (no retry loops).
	ParkourFailCooldown = 0.35,
	-- Vault: tops up to this high. Deeper than VaultMaxDepth = step up onto it instead.
	VaultMaxHeight = 4.5,
	VaultMaxDepth = 4,
	VaultClearance = 0.3, -- how far the feet clear the top
	VaultRiseSpeed = 40, -- fastest rise (studs/s)
	VaultMinSpeedShare = 0.9, -- you keep your speed, at least this share of run speed
	VaultLateSpeedShare = 0.75, -- a vault that starts close keeps solid forward momentum
	-- Ledges: how high above your feet your hands reach. Tops up to this are climbed: sprint into
	-- them from the ground (above VaultMaxHeight), or jump at them (keys on the ledge) and grab
	-- them in the air. Anything taller is a wall: jump to grab it, or wall hop.
	LedgeReach = 6.5,
	-- In the air, a ledge only gets grabbed if it's at least this far above your feet (lower =
	-- you just land on it), and its face is within this many studs (+ a little per speed).
	LedgeAirMin = 0.3,
	LedgeGrabDistance = 1.8,
	-- Half the body's width: a ledge you'd stand on must be this wide on both sides of you
	-- (you're shifted sideways onto it near a corner, otherwise it doesn't happen).
	LedgeBodyHalfWidth = 0.9,
	ClimbSpeed = 30, -- up the wall
	ClimbOverSpeed = 24, -- pulling over the edge
	ClimbApproachMaxSpeed = 26, -- fastest you close in on the wall before going up
	ClimbExitSpeed = 20, -- comes out of a climb maintaining sprint momentum
	-- Slide: gaps at least this tall (feet to the underside) can be slid under.
	SlideMinClearance = 2.3,
	-- While sliding, only a low box (LowerColliderGap to LowerColliderGap + 1.1 above the feet)
	-- collides; the Humanoid keeps your height like running. The lean is visual.
	SlideLean = 70, -- degrees the body leans back (visual)
	SlideVisualDrop = 1.7, -- studs the body drops (visual)
	SlideMaxTime = 2.5, -- stand up after this long if there's room
	SlideFriction = 6, -- speed lost per second (never below walk speed)
	SlideMinTime = 0.35,
	SlideSteerRate = 90, -- degrees per second you can steer a slide
	-- Space during a slide (or this long before it started) jumps out with the slide's speed as soon
	-- as you've cleared what you slid under.
	SlideJumpWindow = 0.2,
	-- Top speed any carried momentum can reach (dash-jump takeoff, a dash handed to a vault /
	-- slide / climb). Scaled by the HP speed multiplier.
	MomentumMaxSpeed = 50,

	-- STAMINA -------------------------------------------------------------------
	-- One stamina meter for every fighter; each race's special (Left Ctrl) spends it its own way.
	-- It comes back after StaminaRegenDelay seconds of not spending, faster on the ground.
	StaminaMax = 100,
	StaminaRegenDelay = 0.9,
	StaminaRegenGround = 45, -- per second
	StaminaRegenAir = 18, -- per second

	-- RACES -----------------------------------------------------------------------
	-- Until the loadout menu exists, every player spawns as this race ("Moth" or "" for none).
	DefaultRace = "Moth",

	-- MOTH: LANTERN + WINGS (Left Ctrl) --------------------------------------------
	-- The lantern hangs on the hip. Left Ctrl:
	--   TAP (lantern on the hip)  -> WING FLIGHT: spread the wings and fly ~WingFlightDistance studs
	--                                where the camera looks, then keep some of the speed. Costs a big
	--                                chunk of stamina. M1 cancels it (and throws an M1 right away).
	--   HOLD (lantern on the hip) -> take the lantern in hand and charge the throw; RELEASE throws it
	--                                at the crosshair. Longer hold = faster, farther throw.
	--   PRESS while it's in the air -> it stops and hangs there (once per throw) for
	--                                LanternSuspendTime, showing its light radius. Then it drops.
	--   HOLD (lantern not on you) -> fly: straight to an opponent the lantern hit (tagged), or freely
	--                                inside a hanging lantern's light (you can't leave the light).
	--                                Letting go or M1 ends it.
	-- Touching the lantern grabs it back onto the hip (walking or flying). Grabbing it while flying
	-- gives a burst of speed. After a grab it can't be thrown for LanternGrabCooldown.
	-- A thrown lantern that hits someone: LanternDamage, tags them for LanternTagTime (they're
	-- marked for everyone to see), and it bounces back a little toward you and drops. Where it first
	-- lands (or hits someone) it flashes: opponents within LanternBurstRadius that the flash can SEE
	-- (nothing solid in between) are tagged too, but take no damage.
	-- The throw is a real projectile (LanternPhysics): it goes through the point under the crosshair
	-- (or toward it, as far as the charge's range), then keeps flying until it hits something.
	LanternTapTime = 0.2, -- released sooner than this = tap; held longer = hold (seconds)
	LanternChargeTime = 0.8, -- extra hold time for a full-power throw (seconds)
	LanternThrowSpeedMin = 50, -- launch speed at no charge (studs/s)
	LanternThrowSpeedMax = 110, -- ...at full charge
	LanternThrowRangeMin = 35, -- how far along the crosshair it aims at no charge (studs)
	LanternThrowRangeMax = 90, -- ...at full charge
	LanternThrowGravity = 0.35, -- share of normal gravity while flying out
	LanternMaxFlightTime = 3, -- after this long in the air it just drops (seconds)
	LanternDamage = 3,
	LanternTagTime = 3, -- seconds a hit opponent stays tagged
	LanternBurstRadius = 10, -- the impact flash tags opponents this close that it can see (studs)
	LanternBounceBack = 14, -- after a hit: speed back toward you (studs/s)
	LanternBounceUp = 22, -- ...and upward
	LanternSuspendTime = 5, -- a suspended lantern hangs this long, then drops (seconds)
	LanternLightRadius = 30, -- the suspended lantern's light (studs)
	LanternGrabRadius = 4, -- walk / fly this close to grab it (studs)
	LanternRegrabDelay = 0.35, -- can't grab it again this soon after throwing (seconds)
	LanternGrabCooldown = 2, -- after a grab, no throwing for this long (seconds)
	LanternGrabBurst = 25, -- grabbing it while flying adds this much speed (studs/s)
	LanternGrabBurstMax = 75, -- ...up to this speed
	-- Wing flight (tap).
	WingFlightSpeedMultiplier = 1.2, -- initial fly speed relative to sprint speed (~31.2 studs/s)
	WingFlightDistance = 13, -- distance covered over WingFlightTime at 1.2x sprint speed tapering to run speed
	WingFlightTime = 0.45, -- seconds to cover that distance
	WingFlightCost = 35, -- stamina
	WingFlightKeep = 0.55, -- share of the flight speed you keep after it (momentum)
	WingFlightCooldown = 0.4,
	-- Flight inside the lantern's light (hold).
	FlyStartStamina = 8, -- need at least this much to take off
	FlyDrain = 22, -- stamina per second
	FlySlowSpeed = 18, -- cruising speed without W
	FlyMaxSpeed = 55, -- top speed holding W
	FlySpeedChange = 40, -- how fast the speed changes toward the target (studs/s per second)
	FlySharpTurnRate = 300, -- degrees/s you can turn at FlySlowSpeed
	FlyWideTurnRate = 60, -- degrees/s you can turn at FlyMaxSpeed
	-- Flying straight to a tagged opponent (hold).
	TagFlySpeed = 70,
	TagFlyTurnRate = 720,
	TagFlyStopDistance = 4.5, -- stops this far from their centre, moving with them
	TagFlyMaxTime = 1.2,

	-- DEBUG -----------------------------------------------------------------
	-- On-screen speed counter for testing. Press F3 to hide or show it.
	-- Set to false before release.
	DebugSpeedometer = true,
}

return MovementConfig
