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

print(client.is_connected)

local err = client:publish("test", "Test Message Please Ignore")
if err ~= nil then
    error(err)
end

local err = client:disconnect()
if err ~= nil then
    error(err)
end
```
