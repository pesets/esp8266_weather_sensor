--==========================Module Part======================
local moduleName = ...
local M = {}
_G[moduleName] = M
--==========================Local the UMI and TEMP===========
local adc
local pins

--==========================Local the bitStream==============
local bitStream = {}

---------------------------Read bitStream from DHTXX--------------------------
local function read(pin)

  local bitlength = 0
  adc = -1
  pins = -1

  -- Use Markus Gritsch trick to speed up read/write on GPIO
  local gpio_read = gpio.read
  
  
  for j = 1, 24, 1 do
    bitStream[j] = 0
  end


  -- Step 1:  send out start signal to DHT22
  gpio.mode(pin, gpio.OUTPUT)
  gpio.write(pin, gpio.HIGH)
  tmr.delay(100)
  gpio.write(pin, gpio.LOW)
  tmr.delay(10000)
  gpio.write(pin, gpio.HIGH)
  gpio.mode(pin, gpio.INPUT)

  -- Step 2:  Receive bitStream from DHT11/22
  -- bus will always let up eventually, don't bother with timeout
  while (gpio_read(pin) == 0 ) do end
  local c=0
  while (gpio_read(pin) == 1 and c < 500) do c = c + 1 end
  -- bus will always let up eventually, don't bother with timeout
  while (gpio_read(pin) == 0 ) do end
  c=0
  while (gpio_read(pin) == 1 and c < 500) do c = c + 1 end
  
  -- Step 3: DHT22 send data
  for j = 1, 24, 1 do
    while (gpio_read(pin) == 1 and bitlength < 10 ) do
      bitlength = bitlength + 1
    end
    bitStream[j] = bitlength
    bitlength = 0
    -- bus will always let up eventually, don't bother with timeout
    while (gpio_read(pin) == 0) do end
  end
end
---------------------------Convert the bitStream into Number through DHT11 Ways--------------------------

function M.read(pin)

  read(pin)

  local byte_1 = 0
  local byte_2 = 0
  local byte_3 = 0

  for i = 1, 8, 1 do
    if (bitStream[i] > 3) then
      byte_1 = byte_1 + 2 ^ (8 - i)
    end
  end
  
  for i = 1, 8, 1 do
    if (bitStream[i + 8] > 3) then
      byte_2 = byte_2 + 2 ^ (8 - i)
    end
  end

  for i = 1, 8, 1 do
    if (bitStream[i + 16] > 3) then
      byte_3 = byte_3 + 2 ^ (8 - i)
    end
  end
  
  bitStream = {}

  local summ = byte_1 + byte_2 + 2
  if(summ > 255) then summ = summ - 256 end
  if(summ ~= byte_3) then
    adc = -1
    pins = -1
  else
    adc = byte_1 * 256 + byte_2
    pins = adc / 1024
    adc = adc - pins * 1024
    if(adc > 100) then
      adc = (168*1024) / adc
    else
      adc = 0
    end
  end
--  print(string.format("%x %x %x %d %x", byte_1, byte_2, byte_3, adc, pins))
end

function M.getADC()
  return adc
end

function M.getPins()
  return pins
end

return M
