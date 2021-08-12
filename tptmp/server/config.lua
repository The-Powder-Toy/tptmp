local common_config = require("tptmp.common.config")

return {
	-- ***********************************************************************
	-- *** The following options should be customized in accordance with   ***
	-- *** your environment.                                               ***
	-- ***********************************************************************

	-- * Local interface to listen on for player connections. Use "0.0.0.0" for
	--   "all interfaces", "localhost" for localhost, etc.
	host = "0.0.0.0",

	-- * Local interface to listen on for remote console connection, similar to
	--   host. The server does not authenticate remote control clients, so make
	--   sure to not let connections to this port through your firewall. If you
	--   want to connect from another host, use a TLS termination proxy with
	--   peer authentication, and have the proxy connect to this port.
	rcon_host = "localhost",

	-- * Local port to listen on for remote console connections.
	rcon_port = 34405,

	-- * Authenticate clients via the backend specified by auth_backend_* (see
	--   below). secure = true isn't necessary for this, although secure = false
	--   may let authentication tokens be sniffed and used for impersonation.
	-- * WARNING: Running the server with auth = false is currently very poorly
	--   supported by plugins.
	auth = true,

	-- * Max age in seconds for authentication tokens. Only relevant if
	--   auth = true. Specifies the maximum amount of time in seconds between
	--   someone being banned from the authentication backend and being unable
	--   to authenticate with this server.
	token_max_age = 300, -- * Only relevant if auth = true.

	-- * Username to UID cache entry max age in seconds. Only relevant if
	--   auth = true. Specifies the maximum amount of time in seconds between
	--   someone changing usernames on the authentication backend and the first
	--   time authenticating with this server reflects that change.
	offline_user_cache_max_age = 300,

	-- * Specifies whether guests are allowed on the server. Only relevant if
	--   auth = true.
	guests_allowed = true,

	-- * Encrypt traffic between player clients and the server. Requires some
	--   experience with TLS.
	secure = false, -- TODO[fin]: Enable.

	-- * Hostname to check the SNI field in the TLS handshake against. Only
	--   relevant if secure = true. Makes it possible to detect and drop stray,
	--   non-TPTMP connections earlier than via the protocol handshake, which
	--   would otherwise have to time out in the worst case.
	secure_hostname = "tptmp.trigraph.net", -- * TODO[fin]: Replace with tptmp.starcatcher.us

	-- * Path to the public server certificate. Only relevant if secure = true.
	--   This file should not include the intermediary certificates, i.e. the
	--   chain of trust.
	secure_cert_path = "cert.pem",

	-- * Path to the chain of trust behind the server certificate. Only relevant
	--   if secure = true. This file should not include the server certificate.
	secure_chain_path = "chain.pem",
	
	-- * Path to the server private key. Only relevant if secure = true. Common
	--   sense regarding the handling of this file applies.
	secure_pkey_path = "pkey.pem",

	-- * Path to main dynamic configuration store.
	dynamic_config_main = "config.json",

	-- * Path to backup dynamic configuration store.
	dynamic_config_xchg = "config.json~",


	-- ***********************************************************************
	-- *** The following options should be customised in accordance with   ***
	-- *** the policies in effect on your server.                          ***
	-- ***********************************************************************

	-- * Maximum amount of clients connected to the server at any given time.
	--   This does not include clients that have not registered, although new
	--   client connections are dropped if this limit would be violated upon
	--   their registering successfully.
	max_clients = 500,

	-- * Maximum amount of active rooms on the server at any given time. This
	--   does not include inactive rooms with no clients in them but in the
	--   dynamic configuration store.
	max_rooms = 100,

	-- * Maximum amount of rooms in whose owner lists a UID may appear. Only
	--   relevant if auth = true (but auth = false is not supported by the
	--   owner plugin).
	max_rooms_per_owner = 10,

	-- * Maximum amount of UIDs in the owner list of a room. Only relevant if
	--   auth = true (but auth = false is not supported by the owner plugin).
	max_owners_per_room = 10,

	-- * Maximum amount of UIDs in the invite list of a room. Only relevant if
	--   auth = true (but auth = false is not supported by the private plugin).
	max_invites_per_room = 20,

	-- * Maximum amount of UIDs in the block list associated with a UID. Only
	--   relevant if auth = true (but auth = false is not supported by the
	--   block plugin).
	max_blocks_per_user = 100,

	-- * Maximum amount of clients in any room at any given time. Upper
	--   limit is 255, imposed by the protocol.
	max_clients_per_room = 20,

	-- * Maximum amount of connections made from any given host. This does not
	--   include clients that have not registered, although new client
	--   connections are dropped if this limit would be violated upon their
	--   registering successfully.
	-- * WARNING: Must be at least 2 for ghosting to work. This is when a
	--   connection has already ceased to exist on the client side but still
	--   exists on the server side. In this case, a second client connecting
	--   and registering the same UID drops the first, dead connection. This
	--   only works if auth = true.
	max_clients_per_host = 4,

	-- * Specifies the number of times a client may violate the message rate
	--   limit before being dropped for spam.
	max_message_interval_violations = 10,

	-- * Maximum number of characters in the name of a room.
	max_room_name_length = 32,

	-- * Maximum number of characters in the name of a client. If auth = true,
	--   should align with the limit imposed by the authentication backend.
	max_nick_length = 32,


	-- ***********************************************************************
	-- *** The following options should be changed in                      ***
	-- *** tptmp/common/config.lua instead. Since these options should     ***
	-- *** align with the equivalent options on the client side, you       ***
	-- *** will most likely have to ship your own version of the client    ***
	-- *** if you intend to change these.                                  ***
	-- ***********************************************************************

	-- * Port to listen on for player connections.
	port = common_config.port,

	-- * Protocol version.
	version = common_config.version,

	-- * Client-to-server message size limit.
	message_size = common_config.message_size,

	-- * Client-to-server message rate limit.
	message_interval = common_config.message_interval,

	-- * Authentication backend URL. Only relevant if auth = true.
	auth_backend = common_config.auth_backend,

	-- * Authentication backend timeout in seconds. Only relevant if
	---  auth = true.
	auth_backend_timeout = common_config.auth_backend_timeout,

	-- * Username to UID backend URL. Only relevant if auth = true.
	uid_backend = common_config.uid_backend,

	-- * Username to UID backend timeout in seconds. Only relevant if
	---  auth = true.
	uid_backend_timeout = common_config.uid_backend_timeout,


	-- ***********************************************************************
	-- *** The following options should only be changed if you know what   ***
	-- *** you are doing. This usually involves consulting with the        ***
	-- *** developers. Otherwise, these are sane values you should trust.  ***
	-- ***********************************************************************

	-- * Size of the buffer passed to the recv system call. Bigger values
	--   consume more memory, smaller ones incur larger system call overhead.
	read_size = 0x10000,

	-- * Receive queue limit. Specifies the maximum amount of data a client
	--   is allowed to have sent but which the server has not yet had time to
	--   process. A client is dropped if the size of its receive queue exceeds
	--   this limit.
	recvq_limit = 0x200000,

	-- * Send queue limit. Specifies the maximum amount of data a client
	--   is allowed to have not yet processed but which the server has already
	--   queued. A client is dropped if the size of its send queue exceeds
	--   this limit.
	sendq_limit = 0x2000000,

	-- * Send queue flush timeout. Specifies the maximum amount of time in
	--   seconds the server waits for the send queue of a client that is being
	--   dropped to flush. The server makes an effort to send everything from
	--   its send queue (most importantly, the reason for the client being
	--   dropped), but it drops the client earlier if this fails in the
	--   amount of time specified.
	sendq_flush_timeout = 3,

	-- * Send queue flush timeout for the remote console. Similar to
	--   sendq_flush_timeout, except applies to the remote console.
	rcon_sendq_flush_timeout = 3,

	-- * Amount of time in seconds between pings being sent to the client.
	--   Should be half of the ping_timeout option on the client side or less.
	ping_interval = 60,

	-- * Amount of time in seconds a client is allowed to stay connected without
	--   sending a ping. Should be twice the ping_interval option on the client
	--   side or more.
	ping_timeout = 120,

	-- * Amount of time in seconds between pings being sent to the remote
	--   console client. Should be half of the ping timeout on the client side
	--   or less.
	rcon_ping_interval = 60,

	-- * Amount of time in seconds a remote console client is allowed to stay
	--   connected without sending a ping. Should be twice the ping interval on
	--   the client side or more.
	rcon_ping_timeout = 120,


	-- ***********************************************************************
	-- *** The following options should not be changed as their values     ***
	-- *** are tightly coupled with the server implementation.             ***
	-- ***********************************************************************

	-- * Minimum accepted TPT version.
	tpt_version_min = { 96, 1 },

	-- * Maximum accepted TPT version.
	tpt_version_max = { 96, 1 },
}
