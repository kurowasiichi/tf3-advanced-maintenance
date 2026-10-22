-- Service range of a facility: the factor of its catchment radius is a construction parameter (AmConfig.RangeParam),
-- applied by depot_construction.script.tl. Changing it rebuilds the construction with the new parameter, the way the
-- base game changes the cargo of a warehouse stock (entity_window_util.tl).

local config = ug_require "/advanced_maintenance/config.tl" as AmConfig

local range : AmRange = {}

function range.levelOf(factor : number) : AmRangeLevel
	for _, level in ipairs(config.RangeLevels) do
		if math.abs(level.factor - factor) < 0.001 then
			return level
		end
	end
	return config.RangeLevels[1]
end

function range.factorOf(constructionEntity : Engine.Entity) : number
	if constructionEntity == nil or constructionEntity < 0 then
		return 1
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	local params = construction ~= nil and construction.params as table or nil
	local factor = params ~= nil and tonumber(params[config.RangeParam]) or nil
	return factor or 1
end

function range.setFactor(constructionEntity : Engine.Entity, factor : number) : boolean
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if construction == nil then
		return false
	end
	local params = construction.params as table
	params[config.RangeParam] = factor
	local proposal = api.engine.util.proposal.createProposalReplaceConstruction(constructionEntity, params)
	if proposal == nil then
		return false
	end
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true))
	return true
end

return range
