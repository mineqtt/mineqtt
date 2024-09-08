local computer = require("computer")

local mqtt = {}

local safeRead = function (conn, n)
    local success, result, err = pcall(conn.read, conn, n)
    if success then
        return result, err
    end

    return nil, result
end

local readVarint = function (conn, first_byte)
    local b, data, err
    if first_byte == nil then
        data, err = safeRead(conn, 1)
        if err ~= nil then
            return nil, err
        end

        b = string.byte(data)
    else
        b = first_byte
    end

    local n, s = 0, 0
    while b & 0x80 == 0x80 do
        if s > 21 then
            return nil, "number too large"
        end

        n = n + ((b & 0x7F) << s)
        s = s + 7

        data, err = safeRead(conn, 1)
        if err ~= nil then
            return nil, err
        end

        b = string.byte(data)
    end

    return n + (b << s), nil
end

local encodeVarint = function (n)
    if n > 268435455 then
        return nil, "number too large"
    end

    local data = ""
    while n > 127 do
        data = data .. string.char(0x80 | n & 0x7F)
        n = n >> 7
    end

    return data .. string.char(n), nil
end

local MqttClient = {}

function mqtt.open (address, port)
    local conn, err = require("internet").open(address, port)
    if conn == nil then
        return nil, err
    end

    return MqttClient:new(conn), nil
end

function MqttClient:new (conn)
    local c = c or {}
    setmetatable(c, self)
    self.__index = self

    conn.readVarint = readVarint
    conn.safeRead = safeRead
    conn:setTimeout(0)

    c.conn = conn
    c.is_connecting = false
    c.is_connected = false

    return c
end

function MqttClient:handle ()
    if not (self.is_connecting or self.is_connected) then
        return "no connection"
    end

    local data, err = self.conn:safeRead(2)

    if err ~= nil then
        if (string.find(err, "timeout")) then
            return nil
        end

        return err
    end

    local ptype, length, _ = string.unpack("B B", data)

    local length, err = self.conn:readVarint(length)
    if err ~= nil then
        return err
    end

    if length > 0 then
        data, err = self.conn:safeRead(length)
        if err ~= nil then
            return err
        end
    else
        data = ""
    end

    if ptype & 0xF0 == 0x20 then -- CONNACK
        if ptype ~= 0x20 or length < 2 then
            self:disconnect(0x81)
            return "malformed packet"
        end

        local flags, reason, _ = string.unpack("B B", data)

        if flags ~= 0 then
            self:disconnect(0x81)
            return "invalid flags"
        end

        if reason > 127 then
            self.is_connecting = false
            self.is_connected = false
            self.conn:close()
            self.conn = nil
            return "connection closed by server"
        elseif reason ~= 0 then
            self:disconnect(0x81)
            return "unrecognized reason"
        end

        self.is_connecting = false
        self.is_connected = true
    elseif ptype & 0xF0 == 0x40 then -- PUBACK
        -- TODO
    elseif ptype & 0xF0 == 0x90 then -- SUBACK
        -- TODO
    elseif ptype & 0xF0 == 0xD0 then -- PINGRESP
        -- TODO
    elseif ptype & 0xF0 == 0x30 then -- PUBLISH
        local topic, _, next = string.unpack("> s2 B", data)
        local message = string.sub(data, next)

        computer.pushSignal("mqtt_message", topic, message)
    elseif ptype & 0xF0 == 0xE0 then -- DISCONNECT
        if ptype ~= 0xE0 then
            self:disconnect(0x81)
            return "malformed packet"
        end

        self.is_connecting = false
        self.is_connected = false

        if length > 0 then
            reason, _ = string.unpack("B", data)
            if reason ~= 0 then
                return "disconnect with error"
            end
        end

        return "disconnect"
    end

    return nil
end

function MqttClient:connect (username, password)
    if self.is_connecting or self.is_connected then
        return "already connected"
    end

    local length = 13
    local flags = 2
    if username ~= nil then
        length = length + 2 + #username
        flags = flags | 0x80
    end
    if password ~= nil then
        length = length + 2 + #password
        flags = flags | 0x40
    end

    local data = string.char(0x10) .. encodeVarint(length) .. string.pack("> s2 B B I2 B s2", "MQTT", 5, flags, 0, 0, "")
    if username ~= nil then
        data = data .. string.pack("> s2", username)
    end
    if password ~= nil then
        data = data .. string.pack("> s2", password)
    end

    local _, err = self.conn:write(data)
    if err ~= nil then
        return err
    end

    local _, err = self.conn:flush()
    if err ~= nil then
        return err
    end

    self.is_connecting = true

    return nil
end

function MqttClient:publish (topic, payload)
    if not (self.is_connecting or self.is_connected) then
        return "no connection"
    end

    if not topic or #topic == 0 then
        return "topic is required"
    end
    if not payload then
        payload = ""
    end

    local flags = 0
    local length = 3 + #topic + #payload
    local data = string.char(0x30 | flags) .. encodeVarint(length) .. string.pack("> s2 B", topic, 0) .. payload

    local _, err = self.conn:write(data)
    if err ~= nil then
        return err
    end

    local _, err = self.conn:flush()
    if err ~= nil then
        return err
    end

    return nil
end

function MqttClient:subscribe (...)
    if not (self.is_connecting or self.is_connected) then
        return "no connection"
    end

    local count = select('#', ...)

    if count == 0 then
        return "topic is required"
    end

    local packet_id = 1
    local data = string.pack("> I2 B", packet_id, 0)

    for i = 1, count do
        data = data .. string.pack("> s2 B", select(i, ...), 0)
    end

    local header = string.char(0x82) .. encodeVarint(#data)

    local _, err = self.conn:write(header .. data)
    if err ~= nil then
        return err
    end

    local _, err = self.conn:flush()
    if err ~= nil then
        return err
    end

    return nil
end

function MqttClient:disconnect (reason)
    if not (self.is_connecting or self.is_connected) then
        return "no connection"
    end

    if reason == nil then
        reason = 0
    end

    local data = string.pack("> B B B", 0xE0, 1, reason)

    local _, err = self.conn:write(data)
    if err ~= nil then
        return err
    end

    local _, err = self.conn:flush()
    if err ~= nil then
        return err
    end

    self.is_connecting = false
    self.is_connected = false

    self.conn:close()
    self.conn = nil

    return nil
end

return mqtt