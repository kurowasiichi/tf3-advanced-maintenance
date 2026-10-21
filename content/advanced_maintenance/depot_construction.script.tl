-- Replacement for BaseConfig.constructionScript (see mod.script.tl): runs the original construction script, then
-- adds the supply stocks (fuel, furniture, machines) to every subconstruction with a depot. This covers the vehicle
-- depots and maintenance stations of all carriers and the hangar modules of airports (modules are applied by the
-- original script).
--
-- Each supply gets its own stock list, set up like the input stock of an industry (industries/industryutil.lua): an
-- INPUT_STOCK for the cargo and a rule that consumes almost nothing. The cargo reaches it like any industry, through
-- a cargo station whose catchment area covers the facility. The stock holds the supply of the facility (deliveries stop
-- when it is full); the game script takes what the maintained vehicles need out of it.

local util = ug_require "::/scripts/util.tl" as Util
local config = ug_require "/advanced_maintenance/config.tl" as AmConfig

local DefaultConstructionScript <const> = "::scripts/construction/construction.script@constructWithModules"
--- the stock needs a model for its position, the invisible model of the base game keeps it out of sight
local StockModel <const> = "::/assets/stations/air/misc/invisible.mdl"
--- used when the mod parameters give none (see config.tl)
local DefaultStockCapacity <const> = 200
--- The rule makes the stock a destination of the cargo routing like the input of an industry. It consumes almost
--- nothing (the capacity limits the consumption per year): the game script takes what the vehicles need.
local RuleCapacity <const> = 1

local record Settings
	originalScript : string
	stockCapacity : integer
end

local record Ref
	fileName : string
	params : table
end

local record ConstructParams
	constrScript : Ref
	constrParams : table
	scriptParams : table
end

local function translationOf(sub : table) : {number}
	local models = sub.models as {table}
	if models ~= nil and models[1] ~= nil then
		local m = models[1].transf as {number}
		if m ~= nil and #m == 16 then
			return { m[13], m[14], m[15] }
		end
	end
	return { 0, 0, 0 }
end

local function makeStock(depotSub : table, supply : AmSupply, capacity : integer) : table
	local p = translationOf(depotSub)
	return {
		laneLists = {},
		groundFaces = {},
		models = {
			{
				id = StockModel,
				transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, p[1], p[2], p[3], 1 },
			},
		},
		stocks = {
			{
				type = "INPUT_STOCK",
				cargoType = supply.cargo,
				capacity = capacity,
				decayRateFactor = 0,
			},
		},
		rules = {
			{
				input = { { 1 } },
				output = {},
				capacity = RuleCapacity,
			},
		},
		metadata = {},
		-- the tag marks the added subconstructions, so they are never added twice
		tag = supply.tag,
	}
end

local function addStocks(result : table, capacity : integer)
	local subs = result.subconstructions as {table}
	if subs == nil then
		return
	end
	local depots : {table} = {}
	for _, sub in ipairs(subs) do
		for _, supply in ipairs(config.Supplies) do
			if sub.tag == supply.tag then
				return
			end
		end
		if sub.depot ~= nil then
			depots[#depots + 1] = sub
		end
	end
	for _, depotSub in ipairs(depots) do
		for _, supply in ipairs(config.Supplies) do
			subs[#subs + 1] = makeStock(depotSub, supply, capacity)
		end
	end
end

local script = {}

function script.constructWithModules(params : ConstructParams) : table
	local settings : Settings = nil
	if params.scriptParams ~= nil then
		settings = params.scriptParams.advancedMaintenance as Settings
	end
	local original = util.useFn(settings and settings.originalScript or DefaultConstructionScript) as function(ConstructParams) : table
	local result = original(params)
	if result ~= nil then
		-- never break a construction because of the supply stocks
		local ok, err = pcall(function() : boolean
			addStocks(result, settings and settings.stockCapacity or DefaultStockCapacity)
			return true
		end)
		if not ok then
			print("[advanced_maintenance] adding the supply stocks failed: " .. tostring(err))
		end
	end
	return result
end

return script
