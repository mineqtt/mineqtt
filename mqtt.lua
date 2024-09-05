local mqtt = {}

local read_varint = function (conn, first_byte)
    local b
    if first_byte == nil then
        b = conn:read(1)
    else
        b = first_byte
    end

    local n, s = 0, 0
    while b ~= nil and b & 0x80 == 0x80 do
        if s > 21 then
            return 0, "number too large"
        end

        n = n + ((b & 0x7F) << s)
        s = s + 7
        b = conn:read(1)
    end

    if b == nil then
        return n, "eof"
    end

    return n + (b << s), nil
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

    conn.read_varint = read_varint
    conn:setTimeout(1)

    c.conn = conn
    c.is_connecting = false
    c.is_connected = false

    return c
end

function MqttClient:handle ()
    local data = self.conn:read(2)
    if data == nil then
        return "eof"
    end

    local ptype, length, _ = string.unpack("B B", s)

    local length, err = self.conn:read_varint(length)
    if err ~= nil then
        return err
    end

    if length > 0 then
        data = self.conn:read(length)
        if data == nil then
            return "eof"
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

    local length = 15
    local flags = 1
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
