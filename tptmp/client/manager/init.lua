local jacobs = require("tptmp.client.manager.jacobs")
local null   = require("tptmp.client.manager.null")

if rawget(_G, "MANAGER") then
	return jacobs
else
	return null
end
