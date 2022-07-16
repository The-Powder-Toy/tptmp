return {
	-- ***********************************************************************
	-- *** The following options apply to both the server and the clients. ***
	-- *** Handle with care; changing options here means having to update  ***
	-- *** the client you ship.                                            ***
	-- ***********************************************************************

	-- * Protocol version, between 0 and 254. 255 is reserved for future use.
	version = 27,

	-- * Client-to-server message size limit, between 0 and 255, the latter
	--   limit being imposted by the protocol.
	message_size = 200, -- * Upper limit is 255.

	-- * Client-to-server message rate limit. Specifies the amount of time in
	--   seconds that must have elapsed since the previous message in order
	--   for the current message to be processed.
	message_interval = 1,

	-- * Authentication backend URL.
	auth_backend = "https://powdertoy.co.uk/ExternalAuth.api",

	-- * Authentication backend timeout in seconds.
	auth_backend_timeout = 3,

	-- * Username to UID backend URL.
	uid_backend = "https://powdertoy.co.uk/User.json",

	-- * Username to UID backend timeout in seconds.
	uid_backend_timeout = 3,

	-- * Host to connect to by default.
	host = "tptmp.starcatcher.us",

	-- * Port to connect to by default.
	port = 34403,

	-- * Encrypt traffic between player clients and the server.
	secure = true,
}
