# MineQTT

## Installation

### via OPPM

```
oppm register lujoga/oppm
```

```
oppm install mqtt
```

### via interactive Lua shell

```lua
local net = require("internet"); local io = require("io"); local f = io.open("/lib/mqtt.lua", "w"); for line in net.request("https://git.luj0ga.de/luca/mineqtt/raw/branch/main/mqtt.lua") do f:write(line) end; f:flush():close()
```

## Usage

```lua
local mqtt = require("mqtt")
local event = require("event")

local running = true

local client, err = mqtt.open("mqtt.example.org", 1883)
if err ~= nil then
    error(err)
end

local err = client:connect()
if err ~= nil then
    error(err)
end

local err = client:handle()
if err ~= nil then
    error(err)
end

print("connected: ", client.is_connected)

local err = client:publish("test", "Test Message Please Ignore")
if err ~= nil then
    error(err)
end

local err = client:subscribe("test", "test2")
if err ~= nil then
    error(err)
end

local err = client:handle()
if err ~= nil then
    error(err)
end

local mqtt_listener = event.listen("mqtt_message", function(_, topic, message)
    print("received message")
    print("topic: ", topic)
    print("message: ", message)
end)

local int_listener = event.listen("interrupted", function()
    print("interrupted")
    running = false
end)

while running do
    local err = client:handle()
    if err ~= nil then
        print(err)
        running = false;
    end

    os.sleep(0.1)
end

event.cancel(mqtt_listener)
event.cancel(int_listener)


```
