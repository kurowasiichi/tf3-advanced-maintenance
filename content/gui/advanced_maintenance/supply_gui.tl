-- Supply state for the GUI, read from the game script state.

local config = ug_require "/advanced_maintenance/config.tl" as AmConfig

local supply_gui : AmGuiState = {}

function supply_gui.get() : AmState
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(config.GameScript)
	if entity == nil or entity < 0 then
		return nil
	end
	local gameScript = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<AmState>
	return gameScript and gameScript.state or nil
end

function supply_gui.depotOf(entity : Engine.Entity) : Engine.Entity
	if api.engine.getComponent(entity, api.type.ComponentType.VEHICLE_DEPOT) ~= nil then
		return entity
	end
	local constructionEntity = entity
	if api.engine.getComponent(entity, api.type.ComponentType.CONSTRUCTION) == nil then
		constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity)
	end
	local construction = constructionEntity and constructionEntity >= 0
		and api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction or nil
	if construction ~= nil and construction.depots ~= nil and construction.depots[1] ~= nil then
		return construction.depots[1]
	end
	return nil
end

return supply_gui
