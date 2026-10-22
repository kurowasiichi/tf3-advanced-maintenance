-- Finds the supply stocks added to a facility (advanced_maintenance/depot_construction.script.tl), used by the game script and
-- the GUI.

local config = ug_require "/advanced_maintenance/config.tl" as AmConfig

local stock : AmStock = {}

local cargoIds : {string : CargoTypeId} = {}

function stock.cargoId(supply : AmSupply) : CargoTypeId
	local id = cargoIds[supply.key]
	if id == nil then
		id = api.res.cargoTypeRep.find(supply.cargo)
		cargoIds[supply.key] = id
	end
	return id
end

function stock.inConstruction(constructionEntity : Engine.Entity) : {string : Engine.Entity}
	local result : {string : Engine.Entity} = {}
	if constructionEntity == nil or constructionEntity < 0 then
		return result
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if construction == nil or construction.subconstructions == nil or construction.depots == nil or #construction.depots == 0 then
		return result
	end
	local keyOfCargo : {CargoTypeId : string} = {}
	for _, supply in ipairs(config.Supplies) do
		keyOfCargo[stock.cargoId(supply)] = supply.key
	end
	for _, sub in ipairs(construction.subconstructions) do
		local stockList = api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
		if stockList ~= nil and stockList.stocks ~= nil and #stockList.stocks == 1 then
			local key = keyOfCargo[stockList.stocks[1].cargoType]
			if key ~= nil and result[key] == nil then
				result[key] = sub
			end
		end
	end
	return result
end

function stock.find(depot : Engine.Entity) : {string : Engine.Entity}
	return stock.inConstruction(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(depot))
end

function stock.carriesPassengers(tv : Engine.Component.TransportVehicle) : boolean
	-- capacities are indexed by cargo type id + 1 and summed over all wagons (vehicle.tl does the same)
	local capacities = tv.config ~= nil and tv.config.capacities or nil
	local capacity = capacities ~= nil and capacities[api.res.cargoTypeRep.getPassengerCargoTypeId() + 1] or nil
	return capacity ~= nil and capacity > 0
end

function stock.usesSupply(tv : Engine.Component.TransportVehicle, supply : AmSupply) : boolean
	if supply.facilityOnly then
		return false
	end
	return not supply.passengersOnly or stock.carriesPassengers(tv)
end

return stock
