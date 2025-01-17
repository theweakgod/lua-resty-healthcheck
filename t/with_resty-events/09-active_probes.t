use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(1);

plan tests => repeat_each() * 59;

my $pwd = cwd();
$ENV{TEST_NGINX_SERVROOT} = server_root();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;

    init_worker_by_lua_block {
        local we = require "resty.events.compat"
        assert(we.configure({
            unique_timeout = 5,
            broker_id = 0,
            listening = "unix:$ENV{TEST_NGINX_SERVROOT}/worker_events.sock"
        }))
        assert(we.configured())
    }

    server {
        server_name kong_worker_events;
        listen unix:$ENV{TEST_NGINX_SERVROOT}/worker_events.sock;
        access_log off;
        location / {
            content_by_lua_block {
                require("resty.events.compat").run()
            }
        }
    }
};

run_tests();

__DATA__



=== TEST 1: active probes, http node failing
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            return 500;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 3,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            http_failures = 3,
                        }
                    },
                }
            })
            ngx.sleep(2) -- active healthchecks might take some time to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(0.6) -- wait for 6x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))  -- false
        }
    }
--- request
GET /t
--- response_body
false
--- error_log
checking unhealthy targets: nothing to do
unhealthy HTTP increment (1/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy HTTP increment (2/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy HTTP increment (3/3) for '127.0.0.1(127.0.0.1:2114)'
event: target status '127.0.0.1(127.0.0.1:2114)' from 'true' to 'false'
checking healthy targets: nothing to do



=== TEST 2: active probes, http node recovering
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            return 200;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 3,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            http_failures = 3,
                        }
                    },
                }
            })
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, false)
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            ngx.sleep(0.6) -- wait for 6x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))  -- true
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
checking healthy targets: nothing to do
healthy SUCCESS increment (1/3) for '127.0.0.1(127.0.0.1:2114)'
healthy SUCCESS increment (2/3) for '127.0.0.1(127.0.0.1:2114)'
healthy SUCCESS increment (3/3) for '127.0.0.1(127.0.0.1:2114)'
event: target status '127.0.0.1(127.0.0.1:2114)' from 'false' to 'true'
checking unhealthy targets: nothing to do

=== TEST 3: active probes, custom http status (regression test for pre-filled defaults)
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            return 500;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 3,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            http_failures = 3,
                            http_statuses = { 429 },
                        }
                    },
                }
            })
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(0.6) -- wait for 6x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))  -- true
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
checking unhealthy targets: nothing to do
--- no_error_log
checking healthy targets: nothing to do
unhealthy HTTP increment (1/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy HTTP increment (2/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy HTTP increment (3/3) for '127.0.0.1(127.0.0.1:2114)'
event: target status '127.0.0.1(127.0.0.1:2114)' from 'true' to 'false'


=== TEST 4: active probes, custom http status, node failing
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            return 401;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 3,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            http_failures = 3,
                            http_statuses = { 401 },
                        }
                    },
                }
            })
            ngx.sleep(2) -- active healthchecks might take some time to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(0.6) -- wait for 6x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))  -- false
        }
    }
--- request
GET /t
--- response_body
false
--- error_log
checking unhealthy targets: nothing to do
unhealthy HTTP increment (1/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy HTTP increment (2/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy HTTP increment (3/3) for '127.0.0.1(127.0.0.1:2114)'
event: target status '127.0.0.1(127.0.0.1:2114)' from 'true' to 'false'
checking healthy targets: nothing to do



=== TEST 5: active probes, host is correctly set
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            content_by_lua_block {
                if ngx.req.get_headers()["Host"] == "example.com" then
                    ngx.exit(200)
                else
                    ngx.exit(500)
                end
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 1,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            http_failures = 1,
                        }
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, "example.com", false)
            ngx.sleep(0.2) -- wait for 2x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114, "example.com"))  -- true
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
event: target status 'example.com(127.0.0.1:2114)' from 'false' to 'true'
checking unhealthy targets: #1


=== TEST 6: active probes, tcp node failing
--- http_config eval
qq{
    $::HttpConfig
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "tcp",
                checks = {
                    active = {
                        healthy  = {
                            interval = 0.1,
                            successes = 3,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            tcp_failures = 3,
                        }
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            -- Note: no http server configured, so port 2114 remains unanswered
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(0.6) -- wait for 6x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))  -- false
        }
    }
--- request
GET /t
--- response_body
false
--- error_log
checking unhealthy targets: nothing to do
unhealthy TCP increment (1/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy TCP increment (2/3) for '127.0.0.1(127.0.0.1:2114)'
unhealthy TCP increment (3/3) for '127.0.0.1(127.0.0.1:2114)'
event: target status '127.0.0.1(127.0.0.1:2114)' from 'true' to 'false'
checking healthy targets: nothing to do



=== TEST 7: active probes, tcp node recovering
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            return 200;
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "tcp",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 3,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            tcp_failures = 3,
                        }
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, false)
            ngx.sleep(0.6) -- wait for 6x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114))  -- true
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
checking healthy targets: nothing to do
healthy SUCCESS increment (1/3) for '127.0.0.1(127.0.0.1:2114)'
healthy SUCCESS increment (2/3) for '127.0.0.1(127.0.0.1:2114)'
healthy SUCCESS increment (3/3) for '127.0.0.1(127.0.0.1:2114)'
event: target status '127.0.0.1(127.0.0.1:2114)' from 'false' to 'true'
checking unhealthy targets: nothing to do



=== TEST 8: active probes, custom Host header is correctly set
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen 2114;
        location = /status {
            content_by_lua_block {
                if ngx.req.get_headers()["Host"] == "custom-host.test" then
                    ngx.exit(200)
                else
                    ngx.exit(500)
                end
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                name = "testing",
                shm_name = "test_shm",
events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 0.1,
                            successes = 1,
                        },
                        unhealthy  = {
                            interval = 0.1,
                            http_failures = 1,
                        }
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, "example.com", false, "custom-host.test")
            ngx.sleep(0.3) -- wait for 3x the check interval
            ngx.say(checker:get_target_status("127.0.0.1", 2114, "example.com"))  -- true
        }
    }
--- request
GET /t
--- response_body
true
--- error_log
event: target status 'example.com(127.0.0.1:2114)' from 'false' to 'true'
checking unhealthy targets: nothing to do



=== TEST 9: active probes, interval is respected
--- http_config eval
qq{
    $::HttpConfig

    # ignore lua tcp socket read timed out
    lua_socket_log_errors off;

    server {
        listen 2114;
        location = /status {
            access_by_lua_block {
                ngx.sleep(0.3)
                ngx.exit(200)
            }
        }
    }
}
--- config
    location = /t {
        content_by_lua_block {
            local healthcheck = require("resty.healthcheck")
            local checker = healthcheck.new({
                test = true,
                name = "testing",
                shm_name = "test_shm",
                events_module = "resty.events",
                type = "http",
                checks = {
                    active = {
                        http_path = "/status",
                        healthy  = {
                            interval = 1,
                            successes = 1,
                        },
                        unhealthy  = {
                            interval = 1,
                            http_failures = 1,
                        }
                    },
                }
            })
            ngx.sleep(1) -- active healthchecks might take up to 1s to start
            local ok, err = checker:add_target("127.0.0.1", 2114, nil, true)
            ngx.sleep(1) -- wait for the check interval
            -- checker callback should not be called more than 5 times
            if checker.checker_callback_count < 5 then
                ngx.say("OK")
            else
                ngx.say("BAD")
            end
        }
    }
--- request
GET /t
--- response_body
OK
--- no_error_log
[error]
