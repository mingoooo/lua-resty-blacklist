# lua-resty-blacklist

Openresty + Redis 黑名单，多个 Openresty 读取同一个 Reids，实现共享黑名单。

# 工作原理

![ip_blacklist](/doc/pic/ip_blacklist.png)

# 必要条件

- openresty >= 1.11.2.4
- redis

# 安装

## 1. 分配 nginx 本地缓存黑名单、设置同步黑名单任务

修改 nginx.conf，在 http 配置块下，第一个 server 前添加：

```
...
http
{
    # 由 Nginx 进程分配一块 10M 大小的共享内存空间，用来缓存 IP 黑名单
    lua_shared_dict ip_blacklist 10m;

    # 在初始化 nginx worker 时开启同步定时任务
    init_worker_by_lua_file /data/svr/openresty/lualib/ip_blacklist/sync.lua;
...
```

## 2. 上传 lua 脚本 

本例上传到/data/svr/openresty/lualib/

## 3. 修改同步黑名单配置

```
vim /data/svr/openresty/lualib/ip_blacklist/config.lua
```

```
-- redis ip
redis_host = "127.0.0.1"

-- redis port
redis_port = 6379

-- redis 连接超时时间
redis_connection_timeout = 100

-- redis 存储黑名单的 set key
redis_key = "ip_blacklist"

-- 同步黑名单时间间隔（单位：秒）
sync_interval = 60
```

## 4. 添加限制配置

在需要限制的 http、server 或 location 块下添加以下配置

```
vim /data/conf/openresty/vhosts/abc.com
```

```
...
location / {
    access_by_lua_file /data/svr/openresty/lualib/ip_blacklist.lua;
...
```

## 5. reload nginx

```
/data/sh/openresty configtest && /data/sh/openresty reload
```

## 6. 测试

### 6.1 确认添加黑名单前正常访问

```
curl -I http://127.0.0.1
# HTTP/1.1 200 OK
```

### 6.2 添加 ip 到黑名单

```
redis-cli sadd ip_blacklist 127.0.0.1
```

### 6.3 测试添加黑名单后

因为有同步间隔，所以新添加黑名单最长生效时间=同步时间，配置见 3

```
curl -I http://127.0.0.1
# HTTP/1.1 403 Forbidden
```
