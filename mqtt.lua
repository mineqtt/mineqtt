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
    conn:setTimeout(1)

    c.conn = conn
    c.is_connecting = false
    c.is_connected = false

    return c
end

function MqttClient:handle ()
    local data, err = self.conn:safeRead(2)
    if err ~= nil then
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
            return "malformed packet"
        end

        if reason > 127 then
            self.is_connecting = false
            self.is_connected = false
            self.conn:close()
            self.conn = nil
            return "connection closed by server"
        elseif reason ~= 0 then
            self:disconnect(0x81)
            return "malformed packet"
        end

        self.is_connecting = false
        self.is_connected = true
    elseif ptype == 0x40 then -- PUBACK
        -- TODO
    elseif ptype == 0xD0 then -- PINGRESP
        -- TODO
    elseif ptype == 0xE0 then -- DISCONNECT
        -- TODO
    end

    return nil
end

function MqttClient:connect (username, password)
    if self.is_connecting or self.is_connected then
        return nil
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

    if length > 127 then
        return "packet size exceeds current implementation capabilities"
    end

    local data = string.pack("> B B s2 B B I2 B s2", 0x10, length, "MQTT", 5, flags, 0, 0, "")
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

function MqttClient:disconnect (reason)
    if not (self.is_connecting or self.is_connected) then
        return nil
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
