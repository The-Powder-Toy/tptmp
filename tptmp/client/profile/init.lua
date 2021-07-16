local vanilla = require("tptmp.client.profile.vanilla")
local jacobs  = require("tptmp.client.profile.jacobs")

if tpt.version.jacob1s_mod then
	return jacobs
else
	return vanilla
end
