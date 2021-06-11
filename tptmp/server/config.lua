-- * TODO[imm]: document non-trivial options

local common_config = require("tptmp.common.config")

return {
	rcon_host = "localhost",
	rcon_port = 34405,
	auth = true, -- * Authenticate clients. secure = true isn't strictly necessary for this.
	token_max_age = 300, -- * Only relevant if auth = true.
	offline_user_cache_max_age = 300, -- * Only relevant if auth = true.
	guests_allowed = true, -- * Only relevant if auth = true.
	version = common_config.version,
	tpt_version_min = { 91, 4 }, -- * TODO[fin]: Bump to 96.0.
	tpt_version_max = { 95, 0 }, -- * TODO[fin]: Bump to 96.0.
	read_size = 0x1000000,
	recvq_limit = 0x200000,
	sendq_limit = 0x2000000,
	sendq_flush_timeout = 3,
	rcon_sendq_flush_timeout = 3,
	ping_interval = 60,
	ping_timeout = 120,
	host = "0.0.0.0",
	port = common_config.port,
	secure = common_config.secure,
	secure_chain_path = "chain.pem", -- * Only relevant if secure = true.
	secure_cert_path = "cert.pem", -- * Only relevant if secure = true.
	secure_pkey_path = "pkey.pem", -- * Only relevant if secure = true.
	secure_hostname = common_config.host, -- * Only relevant if secure = true.
	max_clients = 500,
	max_rooms = 100,
	max_rooms_per_owner = 10,
	max_owners_per_room = 10,
	max_blocks_per_user = 100,
	max_invites_per_room = 20,
	max_clients_per_room = 20, -- * Upper limit is 255.
	max_clients_per_host = 4, -- * Must be at least 2 for ghosting to work.
	dynamic_config_main = "config.json",
	dynamic_config_xchg = "config.json~",
	message_size = common_config.message_size,
	message_interval = common_config.message_interval,
	max_message_interval_violations = 10,
	auth_backend = common_config.auth_backend,
	auth_backend_timeout = common_config.auth_backend_timeout,
	uid_backend = common_config.uid_backend,
	uid_backend_timeout = common_config.uid_backend_timeout,
	max_room_name_length = 32,
	max_nick_length = 32,
}
