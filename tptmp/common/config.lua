return {
	version = 14, -- * TODO[fin]: Give this a bump.
	ping_interval = 60,
	ping_timeout = 120,
	message_size = 200, -- * Upper limit is 255.
	message_interval = 1,
	auth_backend = "https://powdertoy.co.uk/ExternalAuth.api",
	uid_backend = "https://powdertoy.co.uk/User.json",
	host = "tptmp.trigraph.net", -- * TODO[fin]: Replace with tptmp.starcatcher.us
	port = 34403,
	secure = false, -- * TODO[fin]: Enable.
}
