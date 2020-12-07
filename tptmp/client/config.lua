local common_config = require("tptmp.common.config")

local config = {
	version = common_config.version,
	versionstr = "2.0",
	default_host = common_config.host,
	default_port = common_config.port,
	default_secure = common_config.secure,
	read_size = 0x10000,
	sendq_limit = 0x2000000,
	connect_timeout = 10,
	ping_interval = 60,
	ping_timeout = 120,
	backlog_size = 1000,
	history_size = 1000,
	default_width = 210,
	default_height = 155,
	default_alpha = 150,
	message_size = common_config.message_size,
	message_interval = common_config.message_interval,
	min_width = 150,
	min_height = 107,
	stamp_temp = ".tmp.stm",
	notif_fly_time = 0.1,
	notif_fly_distance = 3,
	word_pattern = "^[A-Za-z0-9-_\128-\255]+$",
	whitespace_pattern = "^ $",
	manager_namespace = "tptmp",
	reconnect_later_timeout = 2,
	print_prefix = "\bt[TPTMP]\bw ",
	auth_backend = common_config.auth_backend,
}
config.default_x = math.floor((sim.XRES - config.default_width) / 2)
config.default_y = math.floor((sim.YRES - config.default_height) / 2)

return config
