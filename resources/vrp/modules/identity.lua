local htmlEntities = module("lib/htmlEntities")

local cfg = module("cfg/identity")
local lang = vRP.lang

local sanitizes = module("cfg/sanitizes")

-- init
Citizen.CreateThread(function()
  db:execute([[
    CREATE TABLE IF NOT EXISTS vrp_user_identities(
      user_id INTEGER,
      registration VARCHAR(20),
      phone VARCHAR(20),
      firstname VARCHAR(50),
      name VARCHAR(50),
      age INTEGER,
      CONSTRAINT pk_user_identities PRIMARY KEY(user_id),
      CONSTRAINT fk_user_identities_users FOREIGN KEY(user_id) REFERENCES vrp_users(id) ON DELETE CASCADE,
      INDEX(registration),
      INDEX(phone)
    );
    ]])
end)

-- api

-- return user identity
function vRP.getUserIdentity(user_id, cbr)
  local rows = db:executeSync("SELECT * FROM vrp_user_identities WHERE user_id = @user_id", {user_id = user_id})
  return rows[1]
end

-- return user_id by registration or nil
function vRP.getUserByRegistration(registration, cbr)
  local rows = db:executeSync("SELECT user_id FROM vrp_user_identities WHERE registration = @registration", {registration = registration or ""})
  if #rows > 0 then
    return rows[1].user_id
  end
end

function vRP.getUserByPhone(phone, cbr)
  local rows = db:executeSync("SELECT user_id FROM vrp_user_identities WHERE phone = @phone", {phone = phone or ""})
  if #rows > 0 then
    return rows[1].user_id
  end
end

function vRP.generateStringNumber(format) -- (ex: DDDLLL, D => digit, L => letter)
  local abyte = string.byte("A")
  local zbyte = string.byte("0")

  local number = ""
  for i=1,#format do
    local char = string.sub(format, i,i)
    if char == "D" then number = number..string.char(zbyte+math.random(0,9))
    elseif char == "L" then number = number..string.char(abyte+math.random(0,25))
    else number = number..char end
  end

  return number
end

function vRP.generateRegistrationNumber(cbr)
  local user_id = nil
  local registration = ""
  repeat
    registration = vRP.generateStringNumber("DDDLLL")
    user_id = vRP.getUserByRegistration(registration)
  until not user_id

  return registration
end

function vRP.generatePhoneNumber(cbr)
  local user_id = nil
  local phone = ""

  repeat
    phone = vRP.generateStringNumber(cfg.phone_format)
    user_id = vRP.getUserByPhone(phone)
  until not user_id

  return phone
end

AddEventHandler("vRP:playerJoin",function(user_id,source,name,last_login)
  if not vRP.getUserIdentity(user_id) then
    local registration = vRP.generateRegistrationNumber()
    local phone = vRP.generatePhoneNumber()
    db:execute("INSERT IGNORE INTO vrp_user_identities(user_id,registration,phone,firstname,name,age) VALUES(@user_id,@registration,@phone,@firstname,@name,@age)", {
      user_id = user_id,
      registration = registration,
      phone = phone,
      firstname = cfg.random_first_names[math.random(1,#cfg.random_first_names)],
      name = cfg.random_last_names[math.random(1,#cfg.random_last_names)],
      age = math.random(25,40)
    })
  end
end)

local cityhall_menu = {name=lang.cityhall.title(),css={top="75px", header_color="rgba(0,125,255,0.75)"}}

local function ch_identity(player,choice)
  local user_id = vRP.getUserId(player)
  if user_id ~= nil then
    local firstname = vRP.prompt(player,lang.cityhall.identity.prompt_firstname(),"")
    if string.len(firstname) >= 2 and string.len(firstname) < 50 then
      firstname = sanitizeString(firstname, sanitizes.name[1], sanitizes.name[2])
      local name = vRP.prompt(player,lang.cityhall.identity.prompt_name(),"")
      if string.len(name) >= 2 and string.len(name) < 50 then
        name = sanitizeString(name, sanitizes.name[1], sanitizes.name[2])
        local age = vRP.prompt(player,lang.cityhall.identity.prompt_age(),"")
        age = parseInt(age)
        if age >= 16 and age <= 150 then
          if vRP.tryPayment(user_id,cfg.new_identity_cost) then
            local registration = vRP.generateRegistrationNumber()
            local phone = vRP.generatePhoneNumber()

            db:execute("UPDATE vrp_user_identities SET firstname = @firstname, name = @name, age = @age, registration = @registration, phone = @phone WHERE user_id = @user_id", {
              user_id = user_id,
              firstname = firstname,
              name = name,
              age = age,
              registration = registration,
              phone = phone
            })

            -- update client registration
            vRPclient.setRegistrationNumber(player,{registration})
            vRPclient.notify(player,{lang.money.paid({cfg.new_identity_cost})})
          else
            vRPclient.notify(player,{lang.money.not_enough()})
          end
        else
          vRPclient.notify(player,{lang.common.invalid_value()})
        end
      else
        vRPclient.notify(player,{lang.common.invalid_value()})
      end
    else
      vRPclient.notify(player,{lang.common.invalid_value()})
    end
  end
end

cityhall_menu[lang.cityhall.identity.title()] = {ch_identity,lang.cityhall.identity.description({cfg.new_identity_cost})}

local function cityhall_enter(source)
  local user_id = vRP.getUserId(source)
  if user_id ~= nil then
    vRP.openMenu(source,cityhall_menu)
  end
end

local function cityhall_leave(source)
  vRP.closeMenu(source)
end

local function build_client_cityhall(source)
  local user_id = vRP.getUserId(source)
  if user_id ~= nil then
    local x,y,z = table.unpack(cfg.city_hall)

    vRPclient.addBlip(source,{x,y,z,cfg.blip[1],cfg.blip[2],lang.cityhall.title()})
    vRPclient.addMarker(source,{x,y,z-1,0.7,0.7,0.5,0,255,125,125,150})

    vRP.setArea(source,"vRP:cityhall",x,y,z,1,1.5,cityhall_enter,cityhall_leave)
  end
end

AddEventHandler("vRP:playerSpawn",function(user_id, source, first_spawn)
  local identity = vRP.getUserIdentity(user_id)
  if identity then
    vRPclient.setRegistrationNumber(source,{identity.registration or "Unset"})
  end

  if first_spawn then
    build_client_cityhall(source)
  end
end)

vRP.registerMenuBuilder("main", function(add, data)
  local player = data.player

  local user_id = vRP.getUserId(player)
  if user_id then
    local identity = vRP.getUserIdentity(user_id)

    if identity then
      local home = ""
      local number = ""

      local content = lang.cityhall.menu.info({
        htmlEntities.encode(identity.name),
        htmlEntities.encode(identity.firstname),
        identity.age,
        identity.registration,
        identity.phone
      })
      local choices = {}
      choices[lang.cityhall.menu.title()] = {function()end, content}

      add(choices)
    end
  end
end)
