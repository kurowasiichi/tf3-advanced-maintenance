-- Hooks the construction script: every construction with a depot (vehicle depots, maintenance stations, the hangars of
-- airports) gets a fuel stock, see advanced_maintenance/depot_construction.script.tl.

local config = ug_require "/advanced_maintenance/config.tl" as AmConfig

local FuelConstructionScript <const> = "advanced_maintenance::/advanced_maintenance/depot_construction.script@constructWithModules"
local DefaultConstructionScript <const> = "::scripts/construction/construction.script@constructWithModules"

local mod = {}

mod.preRunFn = function(_captureParams : table, _configDict : {{string, string}}, allModParams : {string : {string : integer}}, baseConfig : BaseConfig)
	local ref = baseConfig.constructionScript
	local original = ref.fileName
	if original == nil or original == "" then
		original = DefaultConstructionScript
	end
	-- another mod may already have replaced the script, it is called from the wrapper
	local params : table = {}
	if ref.params ~= nil then
		for k, v in pairs(ref.params) do
			params[k] = v
		end
	end
	-- the base script needs the cost scales
	if params.costs == nil then
		params.costs = { infrastructureMaintenanceScale = 1.0, infrastructureCostScale = 1.0 }
	end
	-- the construction scripts cannot read the mod parameters, the stock capacity is passed along
	local capacity = config.capacityFromParams(allModParams[config.ModId] as table)
	params.advancedMaintenance = { originalScript = original, stockCapacity = capacity }
	ref.fileName = FuelConstructionScript
	ref.params = params
	baseConfig.constructionScript = ref
end

return mod
