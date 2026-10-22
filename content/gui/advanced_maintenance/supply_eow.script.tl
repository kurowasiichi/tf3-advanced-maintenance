-- GUI of the supplies (registered by the *.res.lua files next to this one):
-- - supply rows (fuel, furniture, machines) below the condition row of the vehicle window, see doReplaceFn
-- - DepotFuelPlugin: supply stocks of the facility in the maintenance station / depot window, shown like the input
--   stocks of an industry

local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local cargo_util = ug_require "::/gui/main/cargo_util.tl" as CargoUtil
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local entity_window_util = ug_require "::/gui/entity_window/entity_window_util.tl" as EntityWindowUtil
local maintenance_station_eow = ug_require "::/gui/entity_window/maintenance_station/maintenance_station_eow.script.tl" as MaintenanceStationEow
local react = ug_require "::/gui/main/react.lua" as React
local vehicle_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl" as VehicleUtil

local config = ug_require "/advanced_maintenance/config.tl" as AmConfig
local supply_gui = ug_require "/gui/advanced_maintenance/supply_gui.tl" as AmGuiState
local stock = ug_require "/advanced_maintenance/stock.tl" as AmStock
local range = ug_require "/advanced_maintenance/range.tl" as AmRange

local RefreshInterval <const> = 1.0
--- icon of the condition row in the vehicle window (vehicle_eow.script.tl, VehicleConditionPlugin)
local ConditionIcon <const> = "::/gui/entity_window/icons/symbol_tools.tga"

local record SupplyEow
	DepotFuelPlugin : Recipe<MaintenanceStationEow.MaintenanceStationWidgetPluginParams>
	doReplaceFn : function(ReactReplacementApi)
end

local supply_eow : SupplyEow = {}

local record EntityParam
	entityId : Engine.Entity
end

local function text(s : string) : TreeNodeId
	return builtin.TextView{ text = s }
end

local function cargoOf(supply : AmSupply) : CargoType
	return api.res.cargoTypeRep.get(stock.cargoId(supply))
end

-- vehicle window ------------------------------------------------------------------------------------------------------

local record SupplyRowParam
	entityId : Engine.Entity
	supply : AmSupply
end

--- a supply row, laid out like the condition row above it
local SupplyRow = react.RegisterRecipe("AmSupplyRow", function(param : SupplyRowParam) : TreeNodeId
	local key = param.supply.key
	local level = engine_react_util.useStepStateTimer(function() : number
		local s = supply_gui.get()
		if s == nil or s.levels == nil or s.levels[key] == nil then
			return 1
		end
		return s.levels[key][param.entityId] or 1
	end, RefreshInterval):old()

	local value = math.max(0, math.min(1, level))
	local cargo = cargoOf(param.supply)
	-- the root of a recipe must be a layout
	return builtin.BoxLayout{
		child = entity_window_util.RatingBar{
			iconPath = cargo ~= nil and cargo.icon or ConditionIcon,
			-- the same levels as the condition row (very bad ... very good)
			ratingText = vehicle_util.getConditionText(value),
			barTooltip = string.format(_("advanced_maintenance_bar_tooltip"), cargo ~= nil and cargo.name or key, math.floor(value * 100 + 0.5)),
			value = value,
			valueChange = 0,
			snapValueToFractions = false,
			numFractions = 5,
			showIcon = true,
		},
	}
end)

local record ConditionWithSuppliesParam
	condition : EntityWindowUtil.RatingBarParam
	vehicle : Engine.Entity
end

local ConditionWithSupplies = react.RegisterRecipe("AmConditionWithSupplies", function(param : ConditionWithSuppliesParam) : TreeNodeId
	local children : {TreeNodeId} = { entity_window_util.RatingBar(param.condition) }
	local tv = api.engine.getComponent(param.vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
	for __, supply in ipairs(config.Supplies) do
		-- no furniture row for vehicles without passengers
		if tv == nil or stock.usesSupply(tv, supply) then
			children[#children + 1] = SupplyRow{ entityId = param.vehicle, supply = supply }
		end
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

-- VehicleConditionPlugin (vehicle_eow.script.tl) renders the condition row in one synchronous call:
--   useStepState(makeVehicleMaintenanceState)    -- the getter calls getAvgMaintenanceState(params.entityId)
--   content_card.makeRecipeAndParam(entity_window_util.RatingBar, { iconPath = <tools icon>, ... })
-- The GUI has no debug.getlocal, so the vehicle is found by calling the latest step state getter once more and
-- capturing the vehicle it passes to getAvgMaintenanceState.

--- the getter passed to the latest engine_react_util.useStepState call
local lastStepGetter : function() : any = nil
local capturedVehicle : Engine.Entity = nil

local function wrapVehicleLookup()
	local util = engine_react_util as table
	local originalUse = util.useStepState as function(any, ...: any) : any...
	util.useStepState = function(getter : any, ...: any) : any...
		lastStepGetter = getter as function() : any
		return originalUse(getter, ...)
	end
	local vehicles = vehicle_util as table
	local originalAvg = vehicles.getAvgMaintenanceState as function(Engine.Entity) : number, number
	vehicles.getAvgMaintenanceState = function(vehicle : Engine.Entity) : number, number
		capturedVehicle = vehicle
		return originalAvg(vehicle)
	end
end

--- the vehicle of the VehicleConditionPlugin that is creating its condition row
local function callingVehicle() : Engine.Entity
	if lastStepGetter == nil then
		return nil
	end
	capturedVehicle = nil
	pcall(lastStepGetter)
	local vehicle = capturedVehicle
	capturedVehicle = nil
	if vehicle ~= nil and api.engine.entityExists(vehicle)
			and api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) ~= nil then
		return vehicle
	end
	return nil
end

--- The condition card of the vehicle window (VehicleConditionPlugin) is a local part of vehicle_eow.script.tl. Its
--- condition row is created by content_card.makeRecipeAndParam(entity_window_util.RatingBar, ...) with the tools icon:
--- that call is wrapped so the card shows the condition row followed by the supply rows.
local function wrapConditionRow()
	local holder = content_card as table
	if holder.amWrapped then
		return
	end
	holder.amWrapped = true
	wrapVehicleLookup()
	local original = content_card.makeRecipeAndParam
	content_card.makeRecipeAndParam = function<T>(recipe : Recipe<T>, param : T) : ContentCard.RecipeAndParamErased
		if recipe as table == entity_window_util.RatingBar as table and param ~= nil
				and (param as EntityWindowUtil.RatingBarParam).iconPath == ConditionIcon then
			local vehicle = callingVehicle()
			if vehicle ~= nil then
				return original(ConditionWithSupplies, { condition = param as EntityWindowUtil.RatingBarParam, vehicle = vehicle })
			end
		end
		return original(recipe, param)
	end
end

-- maintenance facility window -----------------------------------------------------------------------------------------

--- the stock shown by the stock card: the first supply stock of the construction, the others are added to it
local function primaryStock(stocks : {string : Engine.Entity}) : Engine.Entity
	for __, supply in ipairs(config.Supplies) do
		if stocks[supply.key] ~= nil then
			return stocks[supply.key]
		end
	end
	return -1
end

--- The supply stocks of the construction of a stock list entity, and which of them the entity is.
local record StockInfo
	stocks : {string : Engine.Entity}
	key : string
	depot : Engine.Entity
end

local function stockInfo(entity : Engine.Entity) : StockInfo
	local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity)
	local stocks = stock.inConstruction(constructionEntity)
	for key, e in pairs(stocks) do
		if e == entity then
			local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
			return { stocks = stocks, key = key, depot = construction.depots[1] }
		end
	end
	return nil
end

--- while deliveries are switched off the stock is kept full, the units really stored are AmDepotStock.reserve
local function showReserve(configs : {CargoUtil.StockConfig}, depot : Engine.Entity, key : string)
	local s = supply_gui.get()
	local d = s ~= nil and s.depots ~= nil and s.depots[depot] or nil
	local ds = d ~= nil and d.stocks ~= nil and d.stocks[key] or nil
	if ds == nil or ds.reserve == nil then
		return
	end
	for __, c in ipairs(configs) do
		c.stored = ds.reserve
	end
end

--- The stock card (entity_window_util.CombinedStockGroupedCounts) shows the stocks of one stock list, found by
--- cargo_util.calculateStockConfigs. For the primary supply stock of a facility the configs of the other supply stocks
--- are added, so all supplies are shown in one card.
local function wrapStockConfigs()
	local holder = cargo_util as table
	if holder.amWrapped then
		return
	end
	holder.amWrapped = true
	local original = cargo_util.calculateStockConfigs
	cargo_util.calculateStockConfigs = function(entity : Engine.Entity, max? : integer, calculateQuality? : boolean,
			sortByType? : boolean, showEmpty? : boolean, groupStocks? : boolean, producedOnly? : boolean) : {CargoUtil.StockConfig}, integer, boolean
		local configs, maxIcons, invert = original(entity, max, calculateQuality, sortByType, showEmpty, groupStocks, producedOnly)
		local ok, info = pcall(stockInfo, entity)
		if not ok or info == nil then
			return configs, maxIcons, invert
		end
		configs = configs or {}
		showReserve(configs, info.depot, info.key)
		if primaryStock(info.stocks) == entity then
			for __, supply in ipairs(config.Supplies) do
				local other = info.stocks[supply.key]
				if other ~= nil and other ~= entity then
					local otherConfigs = original(other, max, calculateQuality, sortByType, showEmpty, groupStocks, producedOnly) or {}
					showReserve(otherConfigs, info.depot, supply.key)
					for __, c in ipairs(otherConfigs) do
						configs[#configs + 1] = c
					end
				end
			end
		end
		return configs, maxIcons, invert
	end
end

local NoStockText = react.RegisterRecipe("AmNoStockText", function() : TreeNodeId
	return builtin.BoxLayout{ child = text(_("advanced_maintenance_depot_no_stock")) }
end)

local record SuppliedCount
	served : integer
	--- maintained vehicles that use the supply, and those of them that still have some
	users : {string : integer}
	supplied : {string : integer}
end

--- expanded part of the stock card: supplies of the maintained vehicles
local DepotVehicles = react.RegisterRecipe("AmDepotVehicles", function(param : EntityParam) : TreeNodeId
	local info = engine_react_util.useStepStateTimer(function() : SuppliedCount
		local s = supply_gui.get()
		local depot = supply_gui.depotOf(param.entityId)
		local result : SuppliedCount = { served = 0, users = {}, supplied = {} }
		for __, supply in ipairs(config.Supplies) do
			result.users[supply.key] = 0
			result.supplied[supply.key] = 0
		end
		if depot == nil then
			return result
		end
		for __, vehicle in ipairs(api.engine.system.transportVehicleSystem.getVehiclesForMaintenanceStation(depot) or {}) do
			result.served = result.served + 1
			local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
			for __, supply in ipairs(config.Supplies) do
				if tv ~= nil and stock.usesSupply(tv, supply) then
					result.users[supply.key] = result.users[supply.key] + 1
					local levels = s ~= nil and s.levels ~= nil and s.levels[supply.key] or nil
					if levels == nil or (levels[vehicle] or 1) > 0 then
						result.supplied[supply.key] = result.supplied[supply.key] + 1
					end
				end
			end
		end
		return result
	end, RefreshInterval, function(a : SuppliedCount, b : SuppliedCount) : boolean
		if a.served ~= b.served then
			return false
		end
		for key, n in pairs(a.supplied) do
			if b.supplied[key] ~= n or b.users[key] ~= a.users[key] then
				return false
			end
		end
		return true
	end):old()

	local lines : {TreeNodeId} = {}
	for __, supply in ipairs(config.Supplies) do
		-- tools are used by the facility, not by vehicles
		if not supply.facilityOnly then
			local cargo = cargoOf(supply)
			local name = cargo ~= nil and cargo.name or supply.key
			local line = string.format(_("advanced_maintenance_depot_vehicles"), name, info.supplied[supply.key], info.users[supply.key])
			lines[#lines + 1] = text(line)
		end
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = lines }
end)

local NoOutput = react.RegisterRecipe("AmNoOutput", function() : TreeNodeId
	return builtin.BoxLayout{}
end)

--- the delivery switch of the facility: off makes its stocks accept no cargo (the vehicles are still refilled from what is stored)
local SupplySwitch = react.RegisterRecipe("AmSupplySwitch", function(param : EntityParam) : TreeNodeId
	local depot = supply_gui.depotOf(param.entityId)
	local engineEnabled = engine_react_util.useStepStateTimer(function() : boolean
		return depot == nil or supply_gui.isSupplyEnabled(depot)
	end, 0.25):old()
	-- shows the click at once, until the game script has handled the event
	local pending : ReactStateT<boolean> = react.useState(nil)
	local enabled = engineEnabled
	if pending:old() ~= nil then
		enabled = pending:old()
	end
	return builtin.BoxLayout{
		child = builtin.CheckBox{
			label = _("advanced_maintenance_switch_label"),
			value = enabled and 1 or 0,
			onValueChange = function(v : integer)
				if depot == nil then
					return
				end
				pending:set(v == 1)
				supply_gui.setSupplyEnabled(depot, v == 1)
			end,
		},
	}
end)

--- the service range of the facility: the options rebuild the construction with the factor (advanced_maintenance/range.tl),
--- the game script pays the tools every month
local RangeSelector = react.RegisterRecipe("AmRangeSelector", function(param : EntityParam) : TreeNodeId
	local depot = supply_gui.depotOf(param.entityId)
	local constructionEntity = depot ~= nil and api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(depot) or -1
	local factor = engine_react_util.useStepStateTimer(function() : number
		return range.factorOf(constructionEntity)
	end, RefreshInterval):old()

	local items : {TreeNodeId} = {}
	local selected = 1
	for i, level in ipairs(config.RangeLevels) do
		local label : string
		if level.toolsPerMonth <= 0 then
			label = string.format(_("advanced_maintenance_range_item_free"), tostring(level.factor))
		else
			label = string.format(_("advanced_maintenance_range_item"), tostring(level.factor), level.toolsPerMonth)
		end
		items[#items + 1] = builtin.ComboBoxItem{ value = i, content = text(label) }
		if math.abs(level.factor - factor) < 0.001 then
			selected = i
		end
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.ComboBox{
				value = selected,
				items = items,
				onValueChange = function(v : integer|number|string)
					local level = config.RangeLevels[math.floor(tonumber(v) or 1)]
					if level == nil or constructionEntity < 0 or math.abs(level.factor - factor) < 0.001 then
						return
					end
					if not range.setFactor(constructionEntity, level.factor) then
						log.message("[advanced_maintenance] service range: the game refused the rebuild of " .. tostring(constructionEntity))
					end
				end,
			},
			text(_("advanced_maintenance_range_hint")),
		},
	}
end)

--- The supply stocks are shown with the stock widget of the industry window (IndustryCombinedStockGroupedCountsPlugin).
supply_eow.DepotFuelPlugin = react.RegisterPluginRecipe(maintenance_station_eow.MaintenanceStationEowExtensionPoint, "AmDepotFuelPlugin", function(params : MaintenanceStationEow.MaintenanceStationWidgetPluginParams) : TreeNodeId
	local stockList = engine_react_util.useStepStateTimer(function() : Engine.Entity
		local depot = supply_gui.depotOf(params.entityId)
		return depot ~= nil and primaryStock(stock.find(depot)) or -1
	end, RefreshInterval):old()

	if stockList == nil or stockList < 0 then
		return builtin.BoxLayout{
			child = content_card.ContentCard{
				title = _("advanced_maintenance_title"),
				initialCalloutTextPermanent = "",
				recipeAndParamPermanent = content_card.makeRecipe0(NoStockText),
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
			}
		}
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			entity_window_util.CombinedStockGroupedCounts{
				initialCalloutTextInputPermanent = "",
				-- the stock widget needs the expanded parts (entity_window_util.tl indexes them unconditionally)
				initialCalloutTextInputCollapsible = "",
				recipeAndParamInputCollapsible = entity_window_util.makeRecipeAndParam(DepotVehicles, { entityId = params.entityId }),
				initialCalloutTextOutputPermanent = "",
				initialCalloutTextOutputCollapsible = "",
				recipeAndParamOutputCollapsible = content_card.makeRecipe0(NoOutput),
				cardKey = "advancedMaintenanceStock",
				setCollapsibleExpanded = params.setCollapsibleExpanded,
				getCollapsibleExpanded = params.getCollapsibleExpanded,
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
				showSimplifiedOnly = false,
				entityId = stockList,
			},
			content_card.ContentCard{
				title = _("advanced_maintenance_switch_title"),
				initialCalloutTextPermanent = "",
				recipeAndParamPermanent = content_card.makeRecipeAndParam(SupplySwitch, { entityId = params.entityId }),
				hasPermanentFocusables = true,
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
			},
			content_card.ContentCard{
				title = _("advanced_maintenance_range_title"),
				initialCalloutTextPermanent = "",
				recipeAndParamPermanent = content_card.makeRecipeAndParam(RangeSelector, { entityId = params.entityId }),
				hasPermanentFocusables = true,
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
			},
		},
	}
end)

function supply_eow.doReplaceFn(_replacementApi : ReactReplacementApi)
	wrapConditionRow()
	wrapStockConfigs()
	log.message("[advanced_maintenance] supply rows and stocks added to the vehicle and facility windows")
end

return supply_eow
