local bit = bit
local bit_lshift, bit_bor = bit.lshift, bit.bor

Poker.RefundPlayers = {}

Poker.ConfigGiveCurrency = function(ply, amount)
  if not IsValid(ply) then return end
  ply:PS_GivePoints(amount)
end

Poker.ConfigTakeCurrency = function(ply, amount)
  if not IsValid(ply) then return end
  ply:PS_TakePoints(amount)
end

--compares transformed hands and picks out a winner or a tie
Poker.CalculateStrongestHand = function(hands)
  local hand_values = {}
  for id,hand in pairs(hands) do
    local bShift = 16
    local shifted_nums = {}
    for i = 1,#hand do
      local rank = hand[i]
      shifted_nums[#shifted_nums + 1] = bit_lshift( rank, bShift )
      bShift = bShift - 4
    end
    local strength = bit_bor(unpack(shifted_nums))

    if hand_values[strength] then
      hand_values[strength][#hand_values[strength] + 1] = id
    else
      hand_values[strength] = {id}
    end
  end
  return hand_values[table.maxn(hand_values)]
end
--net messages
util.AddNetworkString( "Poker_Game_Start" )
util.AddNetworkString( "Poker_Hand_Update" )
util.AddNetworkString( "Poker_Hand_Data" )
util.AddNetworkString( "Poker_Host_Settings" )
util.AddNetworkString( "Poker_Player_Action" )
util.AddNetworkString( "Poker_Players_Hand_Data" )
util.AddNetworkString( "Poker_Winner" )
util.AddNetworkString( "Poker_Game_Notify" )

net.Receive("Poker_Host_Settings",function(_, ply)
  if not IsValid(ply) then return end
  local seat = ply:GetVehicle()
  if not IsValid(seat) or not seat.PokerSeat or not seat:IsValidVehicle() then return end
  local pokertable = seat:GetNWEntity( "PokerGame" )
  local host = pokertable:GetHost()
  if not IsValid(host) or host != ply then return end
  local antee = net.ReadInt(32)
  antee = math.Clamp(antee, pokertable.MinAntee, pokertable.MaxAntee)
  for k,_ in pairs(pokertable.Players) do
    local v = Player(k)
    if IsValid(v) and not Poker.ConfigHasCurrency(v, antee) then
      if v == host then timer.Remove("Poker_Host_Decide_Time" .. pokertable:EntIndex()) end
      pokertable.ActivePlayers = pokertable.ActivePlayers - 1
      v:ExitVehicle()
      v:ChatPrint("Too rich for your blood!")
    end
    if IsValid(v) and v == host and Poker.ConfigHasCurrency(v, antee) then
      pokertable:SetAntee(antee)
      net.Start("Poker_Game_Notify")
      net.WriteEntity(pokertable)
      net.WriteEntity(host)
      net.Broadcast()
      timer.Remove("Poker_Host_Decide_Time" .. pokertable:EntIndex())
    end
  end
end)

--Discarding
net.Receive( "Poker_Hand_Data", function(_, ply)
  local ent = ply:GetActivePokerGame()
  if not IsValid(ent) or ent:GetRound() != POKER_DRAWING then return end
  if not ent:GetPlaying() then return end

  local hand = ply.PokerHandInstance
  if not hand or not ply:IsPokerTurn() or ply:HasFolded() then return end
  local amount = net.ReadInt(5)
  if amount > 5 or amount < 0 then return end
  if hand.Deck != ent.Deck then return end
  if amount == 0 then ent:NextTurn(ply) return end

  local discarding = net.ReadTable()

  local Discard = hand:Discard(discarding, amount)
  if not Discard then return end
  local code = hand:GetHandCode()
  local cards = hand.Cards
  local SeatNum = ent.Players[ply:UserID()]
  ply.PokerHandInstance = hand

  net.Start("Poker_Hand_Data")
  local compressedTbl = util.Compress(util.TableToJSON(cards))
  local size = compressedTbl:len()
  net.WriteUInt(size, 32)
  net.WriteData(compressedTbl, size)
  net.WriteInt(code, 5)
  net.Send(ply)

  net.Start("Poker_Hand_Update")
  net.WriteEntity(ply)
  net.WriteEntity(ent)
  net.WriteInt(SeatNum, 5)
  net.WriteInt(amount, 5)
  net.Broadcast()

  ent:NextTurn(ply)
end )
--Betting Round Actions
net.Receive( "Poker_Player_Action", function(_, ply)
  if not IsValid(ply) then return end
  if ply:HasFolded() then return end
  if not ply:IsPokerTurn() then return end

  local action = net.ReadInt(32)
  if action <= 0 or action >= 6 then return end

  local ent = ply:GetActivePokerGame()
  if not IsValid(ent) then return end
  if not ent:GetPlaying() then return end
  local round = ent:GetRound()
  if round == POKER_DRAWING or round == POKER_SHOWDOWN then return end

  local slot = ent.Players[ply:UserID()]
  if not slot then return end

  local bet = ent:GetLastBet()
  local raise = 0

  if action == POKER_CHECK then
    if round != POKER_NEXT_BETTING then return end
    if bet != 0 or bet != ent.BettingLog[ply:UserID()] then return end

    ent:NextTurn(ply)
  end

  if action == POKER_FOLD then
    ply:SetFolded(true)
  end

  if action == POKER_BET and bet == 0 then
    bet = net.ReadInt(32)
    if bet < ent.MinBet or bet > ent.MaxBet then return end
    if not Poker.ConfigHasCurrency(ply, bet) then return end
    ent:ConfigTakeCurrency(ply, bet)
    ent:SetLastBet(bet)
    ent:NextTurn(ply)
  end

  if action == POKER_RAISE and bet != 0 and bet > ent.BettingLog[ply:UserID()] then
    if ply.PokerTimesRaised >= ent.ConfigRaiseLimit then return end
    raise = net.ReadInt(32)

    if raise < ent.MinBet or raise > ent.MaxBet then return end
    local AmtToTake = (bet - ent.BettingLog[ply:UserID()]) + raise
    if not Poker.ConfigHasCurrency(ply, AmtToTake) then return end
    ent:ConfigTakeCurrency(ply, AmtToTake)
    ent:SetLastBet(bet + raise)
    ply.PokerTimesRaised = ply.PokerTimesRaised + 1
    ent:NextTurn(ply)
  end

  if action == POKER_CALL and bet > ent.BettingLog[ply:UserID()] then
    local AmtToTake = bet - ent.BettingLog[ply:UserID()]
    if not Poker.ConfigHasCurrency(ply, AmtToTake) then return end
    ent:ConfigTakeCurrency(ply, AmtToTake)
    ent:NextTurn(ply)
  end

  net.Start("Poker_Player_Action")
  net.WriteEntity(ply)
  net.WriteEntity(ent)
  net.WriteInt(slot, 5)
  net.WriteInt(action, 5)
  if action == POKER_RAISE then
    net.WriteInt(ply.PokerTimesRaised, 5)
    net.WriteInt(bet + raise, 32)
  elseif action == POKER_BET then
    net.WriteInt(bet, 32)
  end
  net.Broadcast()
end )

--hooks
hook.Add( "EntityEmitSound", "Poker_Showdown_Sound_Timing", function( t )
  if t.SoundName != "gmodtower/casino/poker_reveal.mp3" then return end
  if not IsValid(t.Entity) or t.Entity:GetClass() != "poker_five_card" then return end
	local time = SoundDuration( t.SoundName )
  timer.Simple(time, function()
    local ent = t.Entity
    if not IsValid(ent) then return end
    if not next(ent.Players) or ent.ActivePlayers == 0 then return end
    local data = {}
    local WinnerCount = ent.WinnerCount
    for k,seat in pairs(ent.Players) do
      local v = Player(k)
      if IsValid(v) and not v:HasFolded() then
        local IsWinner = ent.Winners[k]
        if IsWinner then
          Poker.ConfigGiveCurrency(v, ent:GetPot() / WinnerCount)
        end
        data[k] = {winner = IsWinner, slot = seat, hand = v:GetPokerHand(), rank = v:GetPokerHandRank()}
      end
    end

    for _,v in pairs(ent.PokerChips) do
      if not v:GetNoDraw() then
        v:SetNoDraw(true)
        v:SetFlexWeight(0, 0)
      end
    end

    net.Start("Poker_Players_Hand_Data")
    net.WriteEntity(ent)
    local compressedTbl = util.Compress(util.TableToJSON(data))
    local size = compressedTbl:len()
    net.WriteUInt(size, 32)
    net.WriteData(compressedTbl, size)
    net.Broadcast()

    ent.HandRevealSndFin = true

    timer.Simple(3.5,function()
      if not IsValid(ent) then return end
      ent:ResetDataTables()
    end)

  end)
  return true
end )
--seat networking help: https://github.com/swampservers/contrib/blob/3f00a9411e7e9f7707b5950682782c898d5883de/lua/entities/ent_chess_board.lua
hook.Add( "PlayerEnteredVehicle", "Poker_Seat_Enter", function( ply, seat )
  if not (IsValid(ply) and IsValid(seat) and seat:IsValidVehicle()) then return end
  if not seat.PokerSeat then return end

  local pokertable = seat:GetNWEntity( "PokerGame" )
  if not IsValid(pokertable) then return end
  if pokertable:GetPlaying() then return end

  pokertable.Players[ply:UserID()] = seat.PlayerSlot

  local players = pokertable.ActivePlayers
  players = players + 1
  ply.CanExitPoker = true
  if not IsValid(pokertable:GetHost()) and players == 1 then
    pokertable:SetHost(ply)
    --ply.CanExitPoker = false
  end
  pokertable.ActivePlayers = players
  ply:GodEnable()
end)

hook.Add( "CanExitVehicle", "Poker_Seat_Can_Exit", function( seat, ply )
  if not (IsValid(ply) and IsValid(seat) and seat:IsValidVehicle()) then return end
  if not seat.PokerSeat then return end
  local pokertable = seat:GetNWEntity( "PokerGame" )
  if not IsValid(pokertable) then return end
  if pokertable:GetPlaying() and not ply.CanExitPoker then return false end
  if pokertable:GetHost() == ply and not ply.CanExitPoker then return false end
end)

hook.Add( "CanPlayerEnterVehicle", "Poker_Seat_Can_Join", function( ply, seat )
  if not (IsValid(ply) and IsValid(seat) and seat:IsValidVehicle()) then return end
  if not seat.PokerSeat then return end
  local pokertable = seat:GetNWEntity( "PokerGame" )
  if not IsValid(pokertable) then return end
  if not pokertable:GetPlaying() and not Poker.ConfigHasCurrency(ply, pokertable:GetAntee()) then
    ply:ChatPrint("You can't pay the antee!")
    return false
  end
  if pokertable:GetPlaying() then return false end
  return true
end)

hook.Add( "PhysgunPickup", "Poker_Pick_Up", function( ply, ent )
  if not (IsValid(ply) and IsValid(ent)) then return end
  if ent:GetClass() == "poker_five_card" then return false end
  if ent:IsVehicle() and ent.PokerSeat then return false end
end)

hook.Add( "PlayerLeaveVehicle", "Poker_Seat_Leave", function( ply, seat )
		if not (IsValid(ply) and IsValid(seat) and seat:IsValidVehicle()) then return end
		if not seat.PokerSeat then return end
    if ply:Alive() then
      ply:SetPos( seat:GetPos() - (seat:GetForward() * 40) )
      ply:SetEyeAngles( seat:GetAngles() + Angle(0,90,0) )
    end
    ply:GodDisable()
    ply:SetIsInPoker(false)
    ply:SetActivePokerGame(NULL)
    ply:SetPokerTurn(false)
    ply:SetFolded(false)

    local pokertable = seat:GetNWEntity( "PokerGame" )
    if not IsValid(pokertable) then return end

    if pokertable:GetPlaying() and not ply.CanExitPoker then
      timer.Simple(0, function() if IsValid(ply) and IsValid(seat) and seat:IsValidVehicle() then ply:EnterVehicle(seat) end end)
      return false
    end

    if pokertable.Players[ply:UserID()] then
      pokertable.BettingLog[ply:UserID()] = nil
      pokertable.CurrencyLog[ply:AccountID()] = nil
      pokertable.Players[ply:UserID()] = nil
    end
    if pokertable:GetHost() == ply and not pokertable:GetPlaying() then
      for k,v in pairs(pokertable.Players) do
        local v = Player(k)
        if IsValid(v) and v != ply then
          v:ExitVehicle()
          v:ChatPrint("The host has abandoned the game!")
        end
      end
      pokertable.Players = {}
      pokertable.ActivePlayers = 0
      pokertable:SetHost(NULL)
      if timer.Exists( "Poker_Waiting_For_Plys" .. pokertable:EntIndex() ) then
        timer.Remove( "Poker_Waiting_For_Plys" .. pokertable:EntIndex() )
      end
    end
end)

hook.Add( "PlayerDisconnected", "Poker_Disconnect", function( ply )
	if not (IsValid(ply) or ply:IsInPoker()) then return end
  local pokertable = ply:GetActivePokerGame()
  if not IsValid(pokertable) then return end
  if not pokertable:GetPlaying() then
    pokertable.ActivePlayers = pokertable.ActivePlayers - 1
    pokertable.Players[ply:UserID()] = nil
    return
  end
  if pokertable.Players[ply:UserID()] then
    pokertable.ActivePlayers = pokertable.ActivePlayers - 1
    ply:SetNWBool("PokerHasFolded", true)
    pokertable.BettingLog[ply:UserID()] = nil
    pokertable.CurrencyLog[ply:AccountID()] = nil
    if ply:IsPokerTurn() then
      pokertable:NextTurn(ply)
    else
      pokertable:CheckForWinner()
    end
    pokertable.BettingLog[ply:UserID()] = nil
    pokertable.CurrencyLog[ply:AccountID()] = nil
    pokertable.Players[ply:UserID()] = nil
  end
end)

hook.Add( "CanPlayerSuicide", "Poker_Prevent_Suicide", function( ply )
		if not (IsValid(ply) or ply:IsInPoker()) then return end
		return not ply:IsInPoker()
end)

--In case an badmin decides to slay a player. This does not work with silent slays
--(at least ulx's version) the poker game will soft lock!
--You don't get you're money back if you are slain (might change later)
hook.Add( "PostPlayerDeath", "Poker_Death_Invalidate", function( ply )
		if not (IsValid(ply) or ply:IsInPoker()) then return end
    local pokertable = ply:GetActivePokerGame()
    if not IsValid(pokertable) then return end
    if not pokertable:GetPlaying() then
      pokertable.ActivePlayers = pokertable.ActivePlayers - 1
      pokertable.Players[ply:UserID()] = nil
      return
    end
    ply.CanExitPoker = true
    if pokertable.Players[ply:UserID()] then
      pokertable.ActivePlayers = pokertable.ActivePlayers - 1
      ply:SetNWBool("PokerHasFolded", true)
      if ply:IsPokerTurn() then
        pokertable:NextTurn(ply)
      else
        pokertable:CheckForWinner()
      end
      pokertable.BettingLog[ply:UserID()] = nil
      pokertable.CurrencyLog[ply:AccountID()] = nil
      pokertable.Players[ply:UserID()] = nil
    end
end)

hook.Add("StartCommand", "Poker_Seat_Controls", function(ply, cmd)
  local seat = ply:GetVehicle()
  if IsValid(seat) and seat:IsValidVehicle() and seat.PokerSeat then
    local chair = seat:GetParent()
    local chair_phys = chair:GetPhysicsObject()
    if cmd:KeyDown( IN_MOVELEFT ) and IsValid(chair_phys) then
      chair:SetAngles(chair:GetAngles() + Angle(0,1,0))
      chair_phys:UpdateShadow(chair:GetPos(), chair:GetAngles(), 0 )
    elseif cmd:KeyDown( IN_MOVERIGHT ) and IsValid(chair_phys) then
      chair:SetAngles(chair:GetAngles() - Angle(0,1,0))
      chair_phys:UpdateShadow(chair:GetPos(), chair:GetAngles(), 0 )
    end
  end
end)

hook.Add( "Initialize", "Poker_Initialize", function()
  if not file.Exists("poker_data/", "DATA") then file.CreateDir( "poker_data/" ) end
  if not file.Exists("poker_data/refunds.txt", "DATA") then file.Write( "poker_data/refunds.txt", "{}" ) end
  local data = file.Read( "poker_data/refunds.txt", "DATA" )
  if not data or data == "{}" then return end
  Poker.RefundPlayers = util.JSONToTable(data)
end)

--hopefully server shuts down gracefully
hook.Add( "ShutDown", "Poker_Save_Data", function()
  --if not file.Exists("poker_data/", "DATA") then file.CreateDir( "poker_data/" ) end
  for k, v in ipairs( ents.FindByClass( "poker_five_card" ) ) do
    if IsValid(v) and next(v.CurrencyLog) != nil then
      for id,money in pairs(v.CurrencyLog) do
        Poker.RefundPlayers[id] = money
      end
    end
  end
  file.Write("poker_data/refunds.txt", util.TableToJSON(Poker.RefundPlayers))
end)

hook.Add( "PlayerInitialSpawn", "Poker_Player_Check", function( ply )
	hook.Add( "SetupMove", "Poker_" .. ply:UserID(), function( self, ply, _, cmd )
		if self == ply and not cmd:IsForced() then
      local id = ply:AccountID()
			if Poker.RefundPlayers[id] then
        local amount = Poker.RefundPlayers[id]
        Poker.ConfigGiveCurrency(ply, amount)
        Poker.RefundPlayers[id] = nil
      end
      hook.Remove( "SetupMove",  "Poker_" .. ply:UserID() )
		end
	end )
end )
