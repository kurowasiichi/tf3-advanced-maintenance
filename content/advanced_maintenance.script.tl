-- Supplies of the transport vehicles (AmConfig.Supplies):
-- - fuel: top speed, furniture: comfort, machines: noise and pollution
-- - moving vehicles use every supply, a full fuel supply lasts settings.durationDays calendar days
-- - the settings are the mod parameters (mod.json), they can be changed in the mod settings of a savegame
-- - supplies delivered to a facility are stored in its supply stocks (advanced_maintenance/depot_construction.script.tl);
--   the facility gives them to the vehicles it maintains (TransportVehicle.maintenanceStation): whole units are taken
--   out of the stock (api.cmd.debug.makeStockSetCargoAmountCmd), the rest of a unit waits in the tank of the stock
-- - a vehicle with some of a supply gets its bonus through the vehicle modifiers, without it the base value applies
--
-- The update runs on several threads with separate Lua states: everything that must survive between calls is kept in
-- the game script state, not in module level variables.

local config = ug_require "/advanced_maintenance/config.tl" as AmConfig
local stock = ug_require "/advanced_maintenance/stock.tl" as AmStock
local range = ug_require "/advanced_maintenance/range.tl" as AmRange

local StateVersion <const> = 2
--- 2: the bonuses go through the vehicle modifier game script (VehicleModifier / ChangeModifier events)
local ModifierRevision <const> = 2
--- game time (ms) between two passes over all vehicles
local PassIntervalMs <const> = 2000
--- a vehicle is resupplied when a supply is below this level
local RefillBelow <const> = 0.95
--- calendar day length used when the game speed gives none
local FallbackMillisPerDay <const> = 2000
--- a summary is logged every n-th pass
local LogEveryPasses <const> = 30

local function emptyTables() : {string : {Engine.Entity : number}}
	local t : {string : {Engine.Entity : number}} = {}
	for _, supply in ipairs(config.Supplies) do
		t[supply.key] = {}
	end
	return t
end

local function newState() : AmState
	return {
		version = StateVersion,
		levels = emptyTables(),
		applied = emptyTables(),
		depots = {},
		lastTime = -1,
		passes = 0,
		modifierRevision = ModifierRevision,
	}
end

local function loadState(raw : table) : AmState
	if raw == nil then
		log.message("[advanced_maintenance] state initialized")
		return newState()
	end
	if raw.version == StateVersion then
		local s = raw as AmState
		if s.modifierRevision ~= ModifierRevision then
			-- the bonuses were written to the vehicles directly: hand them to the vehicle modifier script again
			s.applied = emptyTables()
			s.modifierRevision = ModifierRevision
			log.message("[advanced_maintenance] bonuses moved to the vehicle modifier script")
		end
		-- supplies added after the state was created (e.g. the tools) have no tables yet
		for _, supply in ipairs(config.Supplies) do
			s.levels[supply.key] = s.levels[supply.key] or {}
			s.applied[supply.key] = s.applied[supply.key] or {}
		end
		return s
	end
	log.message("[advanced_maintenance] state initialized (unknown version " .. tostring(raw.version) .. ")")
	return newState()
end

local function world() : Engine.Entity
	return api.engine.util.getWorld()
end

local function gameTimeMs() : integer
	local t = api.engine.getComponent(world(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return t.gameTime
end

--- calendar day length in game time ms (GameSpeed.millisPerDay is scaled by the speedup)
local function millisPerDay() : number
	local speed = api.engine.getComponent(world(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	if speed == nil or speed.millisPerDay == nil or speed.millisPerDay <= 0 or speed.speedup == nil or speed.speedup <= 0 then
		return FallbackMillisPerDay
	end
	return speed.millisPerDay * speed.speedup
end

-- supply stocks ------------------------------------------------------------------------------------------------------

local function newDepotStock() : AmDepotStock
	return { tank = 0, stockAtStart = 0, stockLeft = 0, stockList = -1, lastApply = gameTimeMs(), delivered = 0, refueled = 0 }
end

--- units consumed by the stock rule since the last call (each apply of the rule consumes one unit)
local function collectConsumption(d : AmDepotStock) : number
	local stockList = api.engine.getComponent(d.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
	if stockList == nil then
		d.stockList = -1
		return 0
	end
	local units = 0
	local newest = d.lastApply
	for _, ruleData in ipairs(stockList.ruleDatas or {}) do
		for _, apply in ipairs(ruleData.applyHistory or {}) do
			if apply.time > d.lastApply then
				local consumed = apply.consumedCargo ~= nil and #apply.consumedCargo or 0
				units = units + (consumed > 0 and consumed or 1)
				if apply.time > newest then
					newest = apply.time
				end
			end
		end
	end
	d.lastApply = newest
	return units
end


--- writes the stock amount left after the vehicles took their part (while deliveries are switched off, the units are
--- kept in AmDepotStock.reserve and the stock stays full)
local function commitStock(ds : AmDepotStock)
	if ds.reserve ~= nil then
		ds.reserve = ds.stockLeft
		return
	end
	if ds.stockList < 0 or ds.stockLeft == ds.stockAtStart then
		return
	end
	api.cmd.sendCommand(api.cmd.debug.makeStockSetCargoAmountCmd(ds.stockList, 0, ds.stockLeft))
end

local function updateDepots(s : AmState) : {Engine.Entity : boolean}
	local present : {Engine.Entity : boolean} = {}
	api.engine.forEachEntityWithComponent(function(depot : Engine.Entity)
		present[depot] = true
		local d = s.depots[depot]
		if d == nil then
			d = { stocks = {} }
			s.depots[depot] = d
		end
		for _, supply in ipairs(config.Supplies) do
			if d.stocks[supply.key] == nil then
				d.stocks[supply.key] = newDepotStock()
			end
		end

		-- constructions are rebuilt by upgrades, look again from time to time
		local search = s.passes % LogEveryPasses == 0
		for _, ds in pairs(d.stocks) do
			if ds.stockList < 0 then
				search = true
			end
		end
		if search then
			local found = stock.find(depot)
			for _, supply in ipairs(config.Supplies) do
				local ds = d.stocks[supply.key]
				local entity = found[supply.key] or -1
				if entity ~= ds.stockList then
					ds.stockList = entity
					if entity >= 0 then
						log.message("[advanced_maintenance] depot " .. tostring(depot) .. ": " .. supply.key .. " stock " .. tostring(entity))
					end
				end
			end
		end

		local accepting = d.enabled ~= false
		for _, supply in ipairs(config.Supplies) do
			local ds = d.stocks[supply.key]
			ds.stockAtStart = 0
			ds.stockLeft = 0
			if ds.stockList >= 0 then
				local count = api.engine.system.simEntityAtStockSystem.getStockCount(ds.stockList, 0) or 0
				local units = collectConsumption(ds)
				if accepting then
					if ds.reserve ~= nil then
						-- switched on again: the stock gets the units kept aside back and accepts deliveries
						count = ds.reserve
						ds.reserve = nil
						api.cmd.sendCommand(api.cmd.debug.makeStockSetCargoAmountCmd(ds.stockList, 0, count))
						log.message(string.format("[advanced_maintenance] depot %d: %s deliveries on, %d units in stock", depot, supply.key, count))
					elseif units > 0 then
						-- the rule consumes almost nothing, what it does consume goes to the tank as well
						ds.tank = ds.tank + units
						ds.delivered = (ds.delivered or 0) + units
					end
				else
					-- Deliveries switched off: the units are kept aside and the stock is kept full, a full stock is no
					-- destination for the cargo. What the rule consumes of the full stock is not real and is dropped.
					local stockList = api.engine.getComponent(ds.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
					local capacity = stockList ~= nil and stockList.stocks ~= nil and stockList.stocks[1] ~= nil and stockList.stocks[1].capacity or 0
					if ds.reserve == nil then
						ds.reserve = count
						log.message(string.format("[advanced_maintenance] depot %d: %s deliveries off, %d units kept", depot, supply.key, count))
					end
					if capacity > 0 and count < capacity then
						api.cmd.sendCommand(api.cmd.debug.makeStockSetCargoAmountCmd(ds.stockList, 0, capacity))
					end
					count = ds.reserve
				end
				ds.stockAtStart = count
				ds.stockLeft = count
			end
		end
	end, api.type.ComponentType.VEHICLE_DEPOT)
	for depot in pairs(s.depots) do
		if not present[depot] then
			s.depots[depot] = nil
		end
	end
	return present
end

-- vehicles -----------------------------------------------------------------------------------------------------------

--- whether the vehicle uses the transport mode (TransportVehicle.Config.transportModes is a set)
local function hasMode(tv : Engine.Component.TransportVehicle, mode : TransportMode) : boolean
	return tv.config ~= nil and tv.config.transportModes ~= nil and tv.config.transportModes[mode] and true or false
end

--- cargo units for a full supply of the vehicle, relative to a bus (see AmConfig.VehicleFactors)
local function supplySize(tv : Engine.Component.TransportVehicle) : number
	local carriers = api.type["enum"].Carrier
	local modes = api.type["enum"].TransportMode
	local f = config.VehicleFactors
	if tv.carrier == carriers.TRAM then
		return f.tram
	elseif tv.carrier == carriers.RAIL then
		return f.rail
	elseif tv.carrier == carriers.WATER then
		return hasMode(tv, modes.SMALL_SHIP) and f.smallShip or f.ship
	elseif tv.carrier == carriers.AIR then
		return (hasMode(tv, modes.SMALL_AIRCRAFT) or hasMode(tv, modes.HELICOPTER)) and f.smallAircraft or f.aircraft
	end
	return f.road
end

local function isMoving(tv : Engine.Component.TransportVehicle) : boolean
	local states = api.type["enum"].TransportVehicleState
	return tv.state == states.EN_ROUTE or tv.state == states.GOING_TO_DEPOT
end

--- source id of the bonuses in the vehicle modifier game script
local ModifierSource <const> = "advanced_maintenance"

--- Hands the bonuses to the vehicle modifier game script of the base game (vehicle/vehicle_modifier.script.tl), like
--- the landmarks do. It adds up the modifications of all sources and writes the vehicle modifiers; writing them
--- directly would be overwritten whenever another source (e.g. a landmark) changes.
local function applyBonus(vehicle : Engine.Entity, target : {string : number})
	local modifications : {VehicleModifierChanger.Modification : number} = {}
	if target.fuel > 0 then
		modifications.TopSpeed = 1 + target.fuel
	end
	if target.furniture > 0 then
		modifications.Comfort = 1 + target.furniture
	end
	if target.machines > 0 then
		modifications.Noise = 1 - target.machines
		modifications.Pollution = 1 - target.machines
	end
	local changer : VehicleModifierChanger = { entity = vehicle, modifications = modifications, id = ModifierSource }
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "VehicleModifier", "ChangeModifier", changer))
end

local record PassStats
	vehicles : integer
	--- vehicles with some of the supply, per supply key
	supplied : {string : integer}
	refilled : integer
	switched : integer
end

local function updateVehicles(s : AmState, settings : AmSettings, days : number, depots : {Engine.Entity : boolean}) : PassStats
	local use = days / settings.durationDays
	local stats : PassStats = { vehicles = 0, supplied = {}, refilled = 0, switched = 0 }
	for _, supply in ipairs(config.Supplies) do
		stats.supplied[supply.key] = 0
	end
	local present : {Engine.Entity : boolean} = {}
	api.engine.forEachEntityWithComponent(function(vehicle : Engine.Entity)
		local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
		if tv == nil then
			return
		end
		present[vehicle] = true
		stats.vehicles = stats.vehicles + 1

		local moving = isMoving(tv)
		local station = tv.maintenanceStation
		local d = station ~= nil and depots[station] and s.depots[station] or nil
		local size = supplySize(tv)
		local previous : {string : number} = {}
		local target : {string : number} = {}
		local changed = false

		for _, supply in ipairs(config.Supplies) do
			local key = supply.key
			local uses = stock.usesSupply(tv, supply)
			-- new vehicles leave the depot fully supplied; vehicles that do not use the supply (furniture in vehicles
			-- without passengers) have no level, use nothing and get no bonus from it
			local level = uses and (s.levels[key][vehicle] or 1) or 0
			if uses and moving then
				level = math.max(0, level - use * (supply.drainRate or 1))
			end
			local ds = d ~= nil and d.stocks[key] or nil
			if uses and ds ~= nil and ds.stockList >= 0 and level < RefillBelow then
				local need = (1 - level) * size / settings.tanksPerUnit
				-- whole units come out of the stock, the rest of a unit stays in the tank for the next vehicle
				if ds.tank < need and ds.stockLeft > 0 then
					local units = math.min(ds.stockLeft, math.ceil(need - ds.tank))
					ds.stockLeft = ds.stockLeft - units
					ds.tank = ds.tank + units
					ds.delivered = (ds.delivered or 0) + units
				end
				local take = math.min(need, ds.tank)
				if take > 0 then
					ds.tank = ds.tank - take
					ds.refueled = (ds.refueled or 0) + take
					level = math.min(1, level + take * settings.tanksPerUnit / size)
					stats.refilled = stats.refilled + 1
				end
			end
			s.levels[key][vehicle] = uses and level or nil

			previous[key] = s.applied[key][vehicle] or 0
			target[key] = level > 0 and settings.bonus or 0
			if target[key] ~= previous[key] then
				changed = true
			end
			if level > 0 then
				stats.supplied[key] = stats.supplied[key] + 1
			end
		end

		if changed then
			applyBonus(vehicle, target)
			for _, supply in ipairs(config.Supplies) do
				s.applied[supply.key][vehicle] = target[supply.key]
			end
			stats.switched = stats.switched + 1
		end
	end, api.type.ComponentType.TRANSPORT_VEHICLE)

	for _, supply in ipairs(config.Supplies) do
		-- vehicles that do not use a supply only have an applied entry
		for _, t in ipairs({ s.levels[supply.key], s.applied[supply.key] }) do
			for vehicle in pairs(t) do
				if not present[vehicle] then
					t[vehicle] = nil
				end
			end
		end
	end
	return stats
end

-- service range ------------------------------------------------------------------------------------------------------

--- Pays the tools of the service ranges: a new factor pays its first month at once, then every RangeMonthDays. Without
--- enough tools the construction is rebuilt with factor 1.
local function updateRanges(s : AmState, days : number)
	for depot, d in pairs(s.depots) do
		local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(depot)
		local factor = range.factorOf(constructionEntity)
		local level = range.levelOf(factor)
		if level.toolsPerMonth <= 0 then
			d.rangeFactor = 1
			d.rangeDays = 0
		else
			if d.rangeFactor ~= factor then
				d.rangeFactor = factor
				d.rangeDays = config.RangeMonthDays
			else
				d.rangeDays = (d.rangeDays or 0) + days
			end
			if d.rangeDays >= config.RangeMonthDays then
				local ds = d.stocks.tools
				local need = level.toolsPerMonth
				if ds ~= nil and ds.stockList >= 0 and ds.stockLeft >= need then
					ds.stockLeft = ds.stockLeft - need
					d.rangeDays = d.rangeDays - config.RangeMonthDays
					log.message(string.format("[advanced_maintenance] depot %d: service range x%.2f, %d tools used", depot, factor, need))
				else
					-- not enough tools: back to the normal range (the rebuild gives the depot new state if its entity changes)
					local ok, rebuilt = pcall(range.setFactor, constructionEntity, 1)
					log.message(string.format("[advanced_maintenance] depot %d: not enough tools for service range x%.2f (%d needed), back to x1%s",
						depot, factor, need, (ok and rebuilt) and "" or ", rebuild failed: " .. tostring(rebuilt)))
					d.rangeDays = 0
				end
			end
		end
	end
end

-- game script --------------------------------------------------------------------------------------------------------

local function logSummary(s : AmState, settings : AmSettings, stats : PassStats, msPerDay : number)
	local parts : {string} = {}
	for _, supply in ipairs(config.Supplies) do
		local withStock, tank, stocked = 0, 0.0, 0
		for _, d in pairs(s.depots) do
			local ds = d.stocks[supply.key]
			if ds ~= nil and ds.stockList >= 0 then
				withStock = withStock + 1
				tank = tank + ds.tank
				stocked = stocked + (ds.reserve or api.engine.system.simEntityAtStockSystem.getStockCount(ds.stockList, 0))
			end
		end
		parts[#parts + 1] = string.format("%s: %d supplied, %d stocks, in stock %d, taken %.1f",
			supply.key, stats.supplied[supply.key], withStock, stocked, tank)
	end
	log.message(string.format("[advanced_maintenance] %d vehicles (%d refills, %d bonus changes); %s; bonus %.0f%%, %d days, %.2f per unit, day %d ms",
		stats.vehicles, stats.refilled, stats.switched, table.concat(parts, "; "),
		settings.bonus * 100, math.floor(settings.durationDays), settings.tanksPerUnit, math.floor(msPerDay)))
end

local script = {
	update = function(_userParams : table, state : GameScriptState<AmState>, _dt : number) : any
		if not state:hasEventSubscriptions() then
			state:subscribeToEvent(config.SupplySwitchEventName)
		end
		local raw = state:get() as table
		local s = loadState(raw)
		local now = gameTimeMs()
		if s.lastTime < 0 or now < s.lastTime then
			s.lastTime = now
			state:set(s)
			return
		end
		local dt = now - s.lastTime
		if dt < PassIntervalMs then
			if s ~= raw as AmState then
				state:set(s)
			end
			return
		end
		s.lastTime = now
		s.passes = (s.passes or 0) + 1

		local msPerDay = millisPerDay()
		local depots = updateDepots(s)
		local settings = config.clamp(config.fromGame())
		local stats = updateVehicles(s, settings, dt / msPerDay, depots)
		updateRanges(s, dt / msPerDay)
		-- the units the vehicles took leave the stocks
		for _, d in pairs(s.depots) do
			for _, ds in pairs(d.stocks) do
				commitStock(ds)
			end
		end
		if s.passes % LogEveryPasses == 1 then
			logSummary(s, settings, stats, msPerDay)
		end
		state:set(s)
	end,

	--- the delivery switch of a facility window
	handleEvent = function(_userParams : table, state : GameScriptState<AmState>, _src : string, id : string, name : string, param : any) : any
		if id ~= config.EventId or name ~= config.SupplySwitchEventName then
			return
		end
		local e = param as AmSupplySwitchEvent
		if e == nil or e.depot == nil then
			return
		end
		local s = loadState(state:get() as table)
		local d = s.depots[e.depot]
		if d == nil then
			d = { stocks = {} }
			s.depots[e.depot] = d
		end
		-- nil means on, so a facility never switched keeps the default
		if e.enabled then
			d.enabled = nil
		else
			d.enabled = false
		end
		log.message("[advanced_maintenance] depot " .. tostring(e.depot) .. ": deliveries " .. (e.enabled and "on" or "off"))
		state:set(s)
	end,
}

return script
