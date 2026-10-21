-- Registers DepotFuelPlugin (see supply_eow.script.tl).
function data()
	return {
		type = "react-plugin ::MaintenanceStationEowExtensionPoint",
		data = {
			filePath = "advanced_maintenance::/gui/advanced_maintenance/supply_eow.script@DepotFuelPlugin",
			order = 25,
		}
	}
end
