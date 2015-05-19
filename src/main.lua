local SSID = "mywifiap"
local SSID_PASSWORD = "password"

require "dht_lib"

function build_post_request(data_table)
  local data = ""
  for param,value in pairs(data_table) do
    data = data .. param.."="..value.."&"
  end
  request = "POST /update HTTP/1.1\r\n"..
  "Host: api.thingspeak.com\r\n"..
  "Connection: close\r\n"..
  "Content-Type: application/x-www-form-urlencoded\r\n"..
  "Content-Length: "..string.len(data).."\r\n"..
  "\r\n"..
  data
  print(request)
  return request
end

local socket = nil

function post(data)
  print("heap=",node.heap())
  socket = net.createConnection(net.TCP, 0)
  socket:on("receive", function(sck, response) 
--     print(response) 
     poweroff()
  end)
  socket:on("connection", function(sck) 
    print("connected!", socket)
    local post_request = build_post_request(data, flag)
    sck:send(post_request)
--    poweroff()
  end)
-- 184.106.153.149 - ip address for api.thingspeak.com
  socket:connect(80, "184.106.153.149")
end

function div10(x)
  return string.format("%d.%d", x / 10, x % 10)
end

function dataok()
  return dht_lib.getTemperature() and dht_lib.getHumidity()
end

function main()
  tmr.stop(0)
  dht_lib.read(4)
  local data = {key = "my key from thingspeak.com"}
  local ok = false
  if(dataok()) then
    data.field1 = div10(dht_lib.getTemperature())
    data.field2 = div10(dht_lib.getHumidity())
    ok = true
  end
  if(pic.getADC() >= 0) then
    data.field3=div10((pic.getADC() + 5) / 10)
    ok = true
  end
  if(ok) then
    post(data)
  end
end

function poweroff()
  gpio.mode(3, gpio.OUTPUT) 
  gpio.write(3, 0)
end

-- configure ESP as a station
wifi.setmode(wifi.STATION)
wifi.sta.config(SSID, SSID_PASSWORD)
wifi.sta.autoconnect(1)

function check_wifi()
  local ip = wifi.sta.getip()
  if(ip==nil) then
--    print("Connecting...")
  else
    tmr.stop(0)
    print("Connected to AP!")
    print(ip)
    main()
  end
end

tmr.alarm(0, 100, 1, check_wifi)
