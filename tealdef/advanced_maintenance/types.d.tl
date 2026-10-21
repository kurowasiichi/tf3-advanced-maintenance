recordDef = true

--- A supply the maintenance facilities accept and give to the vehicles they maintain (see AmConfig.Supplies).
global record AmSupply
	--- key in the state tables ("fuel", "furniture", "machines")
	key : string
	--- cargo resource
	cargo : string
	--- tag of the stock subconstruction added to the facilities
	tag : integer
	--- speed of use relative to the fuel (1): 0.5 makes a full supply last twice the set days
	drainRate : number
	--- only vehicles that can carry passengers use the supply (and get its bonus)
	passengersOnly : boolean
end

--- Settings, from the mod parameters (mod.json). They apply to every supply.
global record AmSettings
	--- bonus of supplied vehicles (0.2 = fuel: top speed +20 %, furniture: comfort +20 %, machines: noise and
	--- pollution -20 %)
	bonus : number
	--- calendar days a full supply lasts while the vehicle is moving
	durationDays : number
	--- number of empty standard (bus) supplies one cargo unit fills
	tanksPerUnit : number
end

--- One supply stock of a maintenance facility (depot, maintenance station, hangar).
global record AmDepotStock
	--- units taken from the stock and not yet given to vehicles, less than one unit (the stock holds the supply)
	tank : number
	--- units in the stock at the start of the current pass, and what is left after the vehicles took their part
	stockAtStart : integer
	stockLeft : integer
	--- stock list entity (-1 when the construction has none, e.g. built before the mod was added)
	stockList : Engine.Entity
	--- game time of the newest consumption already credited to the tank
	lastApply : integer
	--- units taken from the stock in total (diagnostics)
	delivered : number
	--- units given to vehicles in total (diagnostics)
	refueled : number
end

global record AmDepot
	stocks : {string : AmDepotStock}
end

--- Game script state (advanced_maintenance.script.tl).
global record AmState
	version : integer
	--- supply level 0..1 per supply key and transport vehicle
	levels : {string : {Engine.Entity : number}}
	--- bonus currently applied per supply key and vehicle (0 = none)
	applied : {string : {Engine.Entity : number}}
	depots : {Engine.Entity : AmDepot}
	--- game time (ms) of the last pass
	lastTime : integer
	--- number of passes so far (log and search intervals)
	passes : integer
	--- how the bonuses are applied, see ModifierRevision in advanced_maintenance.script.tl
	modifierRevision : integer
end

--- Cargo units a full supply takes, relative to a bus.
global record AmVehicleFactors
	road : number
	tram : number
	rail : number
	smallShip : number
	ship : number
	--- small aircraft and helicopters
	smallAircraft : number
	aircraft : number
end

--- Mod parameters and constants.
global record AmConfig
	ModId : string
	--- game script resource, see api.engine.system.gameScriptSystem.getEntityForGameScript
	GameScript : string
	--- the supplies in display order
	Supplies : {AmSupply}
	--- capacity of the supply stocks added to the facilities when the parameter is missing
	StockCapacity : integer
	--- capacity of the supply stocks selected in the mod parameters
	capacityFromParams : function(params : table) : integer

	--- the settings selected in the mod parameters
	fromParams : function(params : table) : AmSettings
	fromGame : function() : AmSettings
	--- settings with every value inside the allowed range
	clamp : function(s : AmSettings) : AmSettings
	--- allowed values
	--- values of the duration slider (days), ascending
	DurationSteps : {number}
	--- values of the bonus slider, ascending
	BonusSteps : {number}
	--- cargo units for a full supply per kind of vehicle, relative to a bus
	VehicleFactors : AmVehicleFactors
	--- values of the vehicles per cargo unit slider, ascending
	TanksPerUnitSteps : {number}
end

--- The supply stocks of a facility (advanced_maintenance/stock.tl).
global record AmStock
	cargoId : function(supply : AmSupply) : CargoTypeId
	--- stock list entity per supply key in the construction, missing keys have no stock
	inConstruction : function(constructionEntity : Engine.Entity) : {string : Engine.Entity}
	--- the stocks of the construction of the depot
	find : function(depot : Engine.Entity) : {string : Engine.Entity}
	--- whether the vehicle (any of its wagons) can carry passengers
	carriesPassengers : function(tv : Engine.Component.TransportVehicle) : boolean
	--- whether the vehicle uses the supply, see AmSupply.passengersOnly
	usesSupply : function(tv : Engine.Component.TransportVehicle, supply : AmSupply) : boolean
end

--- Reading the state from the GUI.
global record AmGuiState
	--- the game script state, nil when the game script is not running
	get : function() : AmState
	--- the depot entity of a maintenance facility window (the window may be opened for the depot or for its construction)
	depotOf : function(entity : Engine.Entity) : Engine.Entity
end

recordDef = false
