-- redis ip
redis_host = "127.0.0.1"

-- redis port
redis_port = 6379

-- redis连接超时时间
redis_connection_timeout = 100

-- redis存储黑名单的set key
redis_key_prefix = "blacklist_"

-- 同步黑名单时间间隔（单位：秒）
sync_interval = 60

-- 黑名单缓存文件路径
cache_file = "/tmp/ip_blacklist"
