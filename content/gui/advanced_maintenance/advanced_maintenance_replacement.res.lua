-- Adds the fuel row to the condition card of the vehicle window (see supply_eow.script.tl, doReplaceFn).
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "advanced_maintenance::/gui/advanced_maintenance/supply_eow.script",
			doReplaceFn = "doReplaceFn",
		},
	}
end
