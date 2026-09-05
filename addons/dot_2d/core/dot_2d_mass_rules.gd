@tool
class_name Dot2DMassRules
extends Resource

## How mass becomes size, speed and the right to eat somebody.
##
## The three relationships an agar.io-like game is built out of, in one place, because
## they have to agree: a blob whose drawn radius and whose eat radius come from
## different formulas is a blob that visibly overlaps something it cannot eat.
##
## [b]All three are pure functions of mass.[/b] No state, no randomness, no clock —
## a client predicting an absorption and a server confirming it must reach the same
## answer, and anything else here would be a mispredicted eat.

@export_group("Size")

## Radius at mass 1.
@export_range(0.1, 200.0, 0.1) var base_radius: float = 4.0

## Radius grows as mass to this power.
##
## [b]0.5 is the one that is right.[/b] Area is proportional to radius squared, so a
## blob that has eaten twice its own mass should be √2 times as wide — which is what
## makes two small blobs equal to one big one, and is the whole balance of the genre.
@export_range(0.1, 1.0, 0.05) var radius_exponent: float = 0.5

@export_group("Speed")

## Speed multiplier at mass 1.
@export_range(0.1, 10.0, 0.05) var base_speed_scale: float = 1.0

## Speed falls as mass to this negative power.
##
## Around 0.44 in the original. Zero makes mass free, which is a game where the leader
## simply wins.
@export_range(0.0, 1.5, 0.01) var speed_exponent: float = 0.44

## Speed multiplier never falls below this, whatever the mass.
##
## Without a floor the biggest blob on a long-running server is effectively stationary,
## which is not a challenge, it is a player who has stopped playing.
@export_range(0.05, 1.0, 0.01) var min_speed_scale: float = 0.22

@export_group("Eating")

## How much bigger the eater must be. 1.25 means "a quarter bigger".
@export_range(1.0, 4.0, 0.01) var eat_ratio: float = 1.25

## Fraction of the eater's radius the centres must be within.
##
## 1.0 means the victim's centre must be inside the eater. Below that is stricter and
## reads as "you have to properly cover them", which is what most of these games do.
@export_range(0.1, 1.5, 0.05) var eat_overlap: float = 0.9

## Fraction of the victim's mass the eater gains.
@export_range(0.0, 1.0, 0.05) var absorb_fraction: float = 1.0

@export_group("Decay")

## Fraction of mass lost per second, above [member decay_floor].
##
## The pressure that stops a leader from parking. Small: 0.002 is a fifth of a percent
## a second, which a player who is still eating never notices and a player who has
## stopped does.
@export_range(0.0, 0.2, 0.001) var decay_per_second: float = 0.002

## Mass below which nothing decays.
@export_range(0.0, 10000.0, 1.0) var decay_floor: float = 200.0

@export_group("Splitting")

## Most pieces one player may have.
@export_range(1, 64, 1) var max_pieces: int = 16

## Mass a piece must have to split at all.
@export_range(1.0, 1000.0, 1.0) var min_split_mass: float = 35.0

## Speed a split piece is thrown at.
@export_range(0.0, 3000.0, 10.0) var split_impulse: float = 700.0

## Seconds before two pieces of the same player merge back.
@export_range(0.0, 300.0, 1.0) var merge_delay_sec: float = 15.0


static func agar() -> Dot2DMassRules:
	return Dot2DMassRules.new()


## Radius for a given mass.
func radius_for(mass: float) -> float:
	return base_radius * pow(maxf(0.0001, mass), radius_exponent)


## Mass for a given radius. The inverse of [method radius_for].
##
## Needed when a game places something by size rather than by mass — a pellet field
## drawn to a spec, an editor-placed obstacle.
func mass_for(radius: float) -> float:
	if radius <= 0.0 or base_radius <= 0.0:
		return 0.0
	return pow(radius / base_radius, 1.0 / maxf(0.0001, radius_exponent))


## Speed multiplier for a given mass, never below [member min_speed_scale].
func speed_scale(mass: float) -> float:
	if speed_exponent <= 0.0:
		return base_speed_scale

	var scale := base_speed_scale * pow(maxf(1.0, mass), -speed_exponent)
	return maxf(min_speed_scale, scale)


## Whether [param eater_mass] may eat [param victim_mass] at [param distance].
##
## Both halves in one call, because a game that checks the ratio in one place and the
## distance in another eventually checks only one of them — and the one usually
## forgotten is the distance, which is an eat at any range.
func can_eat(
	eater_mass: float,
	eater_radius: float,
	victim_mass: float,
	distance: float
) -> bool:
	if eater_mass < victim_mass * eat_ratio:
		return false

	return distance <= eater_radius * eat_overlap


## Mass the eater ends up with.
func absorb(eater_mass: float, victim_mass: float) -> float:
	return eater_mass + victim_mass * absorb_fraction


## Mass after [param delta] seconds of decay.
func decay(mass: float, delta: float) -> float:
	if decay_per_second <= 0.0 or mass <= decay_floor:
		return mass

	# Exponential rather than linear, so the rate is the same fraction whatever the
	# mass. A linear rate that is a nuisance at 300 mass is instant death at 30.
	return maxf(decay_floor, mass * pow(1.0 - decay_per_second, delta))


func can_split(mass: float, pieces: int) -> bool:
	return pieces < max_pieces and mass >= min_split_mass


func validate() -> DotResult:
	if eat_ratio <= 1.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"An eat ratio of %.2f lets equal blobs eat each other, which makes the "
				% eat_ratio
			+ "outcome of a collision depend on which one is resolved first."
		)

	if min_speed_scale <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A speed floor of zero means the biggest blob eventually cannot move."
		)

	if radius_exponent >= 1.0:
		DotLog.warn(
			"dot2d.mass",
			"a radius exponent at or above 1 makes mass grow slower than width, "
			+ "so two small blobs are worth more area than one big one"
		)

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"base_radius": base_radius,
		"radius_exponent": radius_exponent,
		"speed_exponent": speed_exponent,
		"min_speed_scale": min_speed_scale,
		"eat_ratio": eat_ratio,
		"decay": decay_per_second,
		"max_pieces": max_pieces,
	}
