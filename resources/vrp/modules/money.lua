local lang = vRP.lang

-- Money module, wallet/bank API
-- The money is managed with direct SQL requests to prevent most potential value corruptions
-- the wallet empty itself when respawning (after death)

-- init tables
Citizen.CreateThread(function()
  db:execute([[
    CREATE TABLE IF NOT EXISTS vrp_user_moneys(
      user_id INTEGER,
      wallet INTEGER,
      bank INTEGER,
      CONSTRAINT pk_user_moneys PRIMARY KEY(user_id),
      CONSTRAINT fk_user_moneys_users FOREIGN KEY(user_id) REFERENCES vrp_users(id) ON DELETE CASCADE
    );
    ]])
end)

-- load config
local cfg = module("cfg/money")

-- API

-- get money
-- cbreturn nil if error
function vRP.getMoney(user_id)
  local tmp = vRP.getUserTmpTable(user_id)
  if tmp then
    return tmp.wallet or 0
  else
    return 0
  end
end

-- set money
function vRP.setMoney(user_id,value)
  local tmp = vRP.getUserTmpTable(user_id)
  if tmp then
    tmp.wallet = value
  end
end

-- try a payment
-- return true or false (debited if true)
function vRP.tryPayment(user_id,amount)
  local money = vRP.getMoney(user_id)
  if amount >= 0 and money >= amount then
    vRP.setMoney(user_id,money-amount)
    return true
  else
    return false
  end
end

-- give money
function vRP.giveMoney(user_id,amount)
  if amount > 0 then
    local money = vRP.getMoney(user_id)
    vRP.setMoney(user_id,money+amount)
  end
end

-- get bank money
function vRP.getBankMoney(user_id)
  local tmp = vRP.getUserTmpTable(user_id)
  if tmp then
    return tmp.bank or 0
  else
    return 0
  end
end

-- set bank money
function vRP.setBankMoney(user_id,value)
  local tmp = vRP.getUserTmpTable(user_id)
  if tmp then
    tmp.bank = value
  end
end

-- give bank money
function vRP.giveBankMoney(user_id,amount)
  if amount > 0 then
    local money = vRP.getBankMoney(user_id)
    vRP.setBankMoney(user_id,money+amount)
  end
end

-- try a withdraw
-- return true or false (withdrawn if true)
function vRP.tryWithdraw(user_id,amount)
  local money = vRP.getBankMoney(user_id)
  if amount >= 0 and money >= amount then
    vRP.setBankMoney(user_id,money-amount)
    vRP.giveMoney(user_id,amount)
    return true
  else
    return false
  end
end

-- try a deposit
-- return true or false (deposited if true)
function vRP.tryDeposit(user_id,amount)
  if amount >= 0 and vRP.tryPayment(user_id,amount) then
    vRP.giveBankMoney(user_id,amount)
    return true
  else
    return false
  end
end

-- try full payment (wallet + bank to complete payment)
-- return true or false (debited if true)
function vRP.tryFullPayment(user_id,amount)
  local money = vRP.getMoney(user_id)
  if money >= amount then -- enough, simple payment
    return vRP.tryPayment(user_id, amount)
  else  -- not enough, withdraw -> payment
    if vRP.tryWithdraw(user_id, amount-money) then -- withdraw to complete amount
      return vRP.tryPayment(user_id, amount)
    end
  end

  return false
end

-- events, init user account if doesn't exist at connection
AddEventHandler("vRP:playerJoin",function(user_id,source,name,last_login)
  db:execute("INSERT IGNORE INTO vrp_user_moneys(user_id,wallet,bank) VALUES(@user_id,@wallet,@bank)", {user_id = user_id, wallet = cfg.open_wallet, bank = cfg.open_bank})
  -- load money (wallet,bank)
  local tmp = vRP.getUserTmpTable(user_id)
  if tmp then
    local rows = db:executeSync("SELECT wallet,bank FROM vrp_user_moneys WHERE user_id = @user_id", {user_id = user_id})
    if #rows > 0 then
      tmp.bank = rows[1].bank
      tmp.wallet = rows[1].wallet
    end
  end
end)

-- save money on leave
AddEventHandler("vRP:playerLeave",function(user_id,source)
  -- (wallet,bank)
  local tmp = vRP.getUserTmpTable(user_id)
  if tmp and tmp.wallet and tmp.bank then
    db:execute("UPDATE vrp_user_moneys SET wallet = @wallet, bank = @bank WHERE user_id = @user_id", {user_id = user_id, wallet = tmp.wallet, bank = tmp.bank})
  end
end)

-- save money (at same time that save datatables)
AddEventHandler("vRP:save", function()
  for k,v in pairs(vRP.user_tmp_tables) do
    if v.wallet and v.bank then
      db:execute("UPDATE vrp_user_moneys SET wallet = @wallet, bank = @bank WHERE user_id = @user_id", {user_id = k, wallet = v.wallet, bank = v.bank})
    end
  end
end)

-- money hud
AddEventHandler("vRP:playerSpawn",function(user_id, source, first_spawn)
  if first_spawn then
    -- add money display
    vRPclient.setDiv(source,{"money",cfg.display_css,lang.money.display({vRP.getMoney(user_id)})})
  end
end)

local function ch_give(player,choice)
  -- get nearest player
  local user_id = vRP.getUserId(player)
  if user_id then
    vRPclient.getNearestPlayer(player,{10}, function(nplayer)
      if nplayer then
        local nuser_id = vRP.getUserId(nplayer)
        if nuser_id then
          -- prompt number
          local amount = vRP.prompt(player,lang.money.give.prompt(),"")
          local amount = parseInt(amount)
          if amount > 0 and vRP.tryPayment(user_id,amount) then
            vRP.giveMoney(nuser_id,amount)
            vRPclient.notify(player,{lang.money.given({amount})})
            vRPclient.notify(nplayer,{lang.money.received({amount})})
          else
            vRPclient.notify(player,{lang.money.not_enough()})
          end
        else
          vRPclient.notify(player,{lang.common.no_player_near()})
        end
      else
        vRPclient.notify(player,{lang.common.no_player_near()})
      end
    end)
  end
end

-- add player give money to main menu
vRP.registerMenuBuilder("main", function(add, data)
  local user_id = vRP.getUserId(data.player)
  if user_id then
    local choices = {}
    choices[lang.money.give.title()] = {ch_give, lang.money.give.description()}

    add(choices)
  end
end)
