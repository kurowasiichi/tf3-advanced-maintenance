-- Mod parameters and constants. The game passes the 1-based index of the selected option, the option values below
-- must match the order of "values" in mod.json. The settings are changed in the mod settings (new game, or the mod
-- selection of a savegame before loading it); the game script reads them in every pass.

local config : AmConfig = {
	ModId = "advanced_maintenance",
	GameScript = "advanced_maintenance::/advanced_maintenance.gs",
	Supplies = {
		-- drainRate: speed of use relative to the fuel (0.5 = a full supply lasts twice the set days)
		-- passengersOnly: only vehicles that can carry passengers use it
		{ key = "fuel", cargo = "::/cargos/fuel/fuel.cargo", tag = 7300, drainRate = 1 },               -- top speed
		{ key = "furniture", cargo = "::/cargos/furniture/furniture.cargo", tag = 7301, drainRate = 0.5, passengersOnly = true }, -- comfort
		{ key = "machines", cargo = "::/cargos/machines/machines.cargo", tag = 7302, drainRate = 0.5 },    -- noise and pollution
		-- facilityOnly: paid monthly for the service range of the facility (RangeLevels), not given to vehicles
		{ key = "tools", cargo = "::/cargos/tools/tools.cargo", tag = 7303, drainRate = 0, facilityOnly = true },
	},
	RangeLevels = {
		{ factor = 1, toolsPerMonth = 0 },
		{ factor = 1.25, toolsPerMonth = 2 },
		{ factor = 1.5, toolsPerMonth = 4 },
		{ factor = 2, toolsPerMonth = 16 },
	},
	RangeParam = "advancedMaintenanceRange",
	RangeMonthDays = 30,
	EventId = "AdvancedMaintenance",
	SupplySwitchEventName = "setSupplyEnabled",
	StockCapacity = 200,
	-- the values of the parameters in mod.json
	DurationSteps = { 30, 60, 90, 120, 180, 360 },
	BonusSteps = { 0.1, 0.2, 0.3 },
	TanksPerUnitSteps = { 0.25, 0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
	-- cargo units for a full supply, relative to a bus
	VehicleFactors = {
		road = 1,
		tram = 2,
		rail = 4,
		smallShip = 2,
		ship = 4,
		smallAircraft = 2,     -- small aircraft and helicopters
		aircraft = 4,
	},
}

local record Option
	values : {number}
	--- 1-based index used when the parameter is missing
	default : integer
end

local Options <const> : {string : Option} = {
	advanced_maintenance_bonus = { values = config.BonusSteps, default = 2 }, -- 20 %
	advanced_maintenance_duration = { values = config.DurationSteps, default = 3 }, -- 90 days
	advanced_maintenance_per_unit = { values = config.TanksPerUnitSteps, default = 4 }, -- 2 vehicles
	advanced_maintenance_capacity = { values = { 100, 200, 400, 800 }, default = 2 }, -- 200 units
}

local function value(params : table, key : string) : number
	local option = Options[key]
	local raw = params ~= nil and tonumber(params[key]) or nil
	local index : integer = raw ~= nil and math.floor(raw) or nil
	if index == nil or option.values[index] == nil then
		index = option.default
	end
	return option.values[index]
end

function config.fromParams(params : table) : AmSettings
	return {
		bonus = value(params, "advanced_maintenance_bonus"),
		durationDays = value(params, "advanced_maintenance_duration"),
		tanksPerUnit = value(params, "advanced_maintenance_per_unit"),
	}
end

function config.capacityFromParams(params : table) : integer
	return math.floor(value(params, "advanced_maintenance_capacity"))
end

function config.fromGame() : AmSettings
	local allParams = api.engine.config.getModParams()
	return config.fromParams(allParams and allParams[config.ModId] as table)
end

local function clampNumber(v : number, min : number, max : number, fallback : number) : number
	if v == nil or v ~= v then
		return fallback
	end
	return math.max(min, math.min(max, v))
end

function config.clamp(s : AmSettings) : AmSettings
	return {
		bonus = clampNumber(s.bonus, config.BonusSteps[1], config.BonusSteps[#config.BonusSteps], 0.2),
		durationDays = clampNumber(s.durationDays, config.DurationSteps[1], config.DurationSteps[#config.DurationSteps], 60),
		tanksPerUnit = clampNumber(s.tanksPerUnit, config.TanksPerUnitSteps[1], config.TanksPerUnitSteps[#config.TanksPerUnitSteps], 2),
	}
end

return config
