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

function supply_gui.isSupplyEnabled(depot : Engine.Entity) : boolean
	local s = supply_gui.get()
	local d = s ~= nil and s.depots ~= nil and s.depots[depot] or nil
	return d == nil or d.enabled ~= false
end

function supply_gui.setSupplyEnabled(depot : Engine.Entity, enabled : boolean)
	local e : AmSupplySwitchEvent = { depot = depot, enabled = enabled }
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", config.EventId, config.SupplySwitchEventName, e))
end

return supply_gui
