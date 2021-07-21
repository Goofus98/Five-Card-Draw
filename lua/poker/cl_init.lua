
Poker.ChatRelay = function(ent, str)
  chat.AddText( Color( 188, 0, 32 ), "[" .. ent.PrintName .. "]: ", color_white, str)
end

net.Receive( "Poker_Game_Notify", function()
  local ent = net.ReadEntity()
  local host = net.ReadEntity()
  timer.Simple(0.2,function()
    if not (IsValid(ent) or IsValid(host)) then return end
    Poker.ChatRelay(ent, host:Nick() .. " is hosting a game with a " .. ent:GetAntee() .. " pt antee!")
  end)
end )

net.Receive( "Poker_Game_Start", function()
  local players = net.ReadInt(5)
  local ent = net.ReadEntity()
  ent.DeckModel:SetPos(ent.DeckOrigin)
  ent.DeckModel:SetRenderOrigin(ent.DeckOrigin)
  ent.PlayersHands = nil
  ent.deck_anim = 0
  ent.Danim = CurTime()
  ent.Prot_x = -65
  ent.Prot_y = 90
  ent.DeckAnim = 1.4
  ent.pot = -1
  ent.WinnersTxt = nil
  ent.HandRevealSndFin = false
  ent.FinishedDeckAnim = false
  if ent == LocalPlayer():GetActivePokerGame() then LocalPlayer().AmountInPot = 0 end
  Poker.ChatRelay(ent, "A game has started with " .. players .. " players!")
  ent:EmitSound("poker/shuffle.wav")
end )
net.Receive( "Poker_Hand_Update", function()
  local ply = net.ReadEntity()
  local ent = net.ReadEntity()
  local seatid = net.ReadInt(5)
  local amt = net.ReadInt(5)

  if LocalPlayer():GetActivePokerGame() == ent and ply != LocalPlayer() then
    Poker.ChatRelay(ent, ply:Nick() .. " discarded " .. amt .. " cards!")
  end
  ent:ThrowFromSeat(seatid, amt, true)
end)

net.Receive( "Poker_Hand_Data", function()
  local ply = LocalPlayer()
  local size = net.ReadUInt(32)
  local data = util.JSONToTable(util.Decompress(net.ReadData(size)))
  ply.PokerHand = data
  ply.HandEval = Poker.HandTypes[net.ReadInt(5)]
  ply.SelectedCards = {}
  ply.CurCard = 1
  ply.PokerHandUnveilAnim = 0
  ply.PokerTimesRaised = 0
  ply.AmountInPot = 0
  surface.PlaySound("poker/notify.wav")
end )

net.Receive( "Poker_Player_Action", function()
  local ply = net.ReadEntity()
  local ent = net.ReadEntity()
  local seatid = net.ReadInt(5)
  local action = net.ReadInt(5)
  if ply == LocalPlayer() and Poker.ActionPanel then Poker.ActionPanel:Close() end
  local chat_text = ""
  if action == POKER_RAISE then
    local times_raised = net.ReadInt(5)
    local raise = net.ReadInt(32)
    chat_text = "raised " .. raise .. " pts!"
    ent:ThrowFromSeat(seatid, 5, false)
    if ply == LocalPlayer() then
      ply.PokerTimesRaised = times_raised
      ply.AmountInPot = raise
    end
  elseif action == POKER_BET then
    local bet = net.ReadInt(32)
    chat_text = "betted " .. bet .. " pts!"
    ent:ThrowFromSeat(seatid, 5, false)
    if ply == LocalPlayer() then
      ply.AmountInPot = bet
    end
  elseif action == POKER_CALL then
    chat_text = "calls!"
    ent:ThrowFromSeat(seatid, 5, false)
    if ply == LocalPlayer() then
      ply.AmountInPot = ent:GetLastBet()
    end
  elseif action == POKER_FOLD then
    chat_text = "has folded!"
    local boneindex = ply:LookupBone("ValveBiped.Bip01_L_Upperarm")
    if boneindex and ply:GetManipulateBoneAngles(boneindex) == Angle(0,70,0) then
      ply:ManipulateBoneAngles( boneindex, Angle(0,0,0)  )
    end
  elseif action == POKER_CHECK then
    chat_text = "checks!"
  end
  if LocalPlayer():GetActivePokerGame() == ent and ply != LocalPlayer() then
    Poker.ChatRelay(ent, ply:Nick() .. " " .. chat_text)
  end
  --LocalPlayer():ChatPrint(chat_text)
end )

net.Receive( "Poker_Host_Settings", function()
  local ent = net.ReadEntity()
  if not IsValid(ent) then return end
  Derma_StringRequest(
  "Host Menu",
  "Decide an antee (" .. ent.MinAntee .. " - " .. ent.MaxAntee .. ")!",
  "",
  function(text)
    local amount = tonumber(text)
    if amount == nil then return end
    net.Start("Poker_Host_Settings")
    net.WriteInt(amount, 32)
    net.SendToServer()
  end,
  function(text)
  end )
end )

net.Receive( "Poker_Players_Hand_Data", function()
  local ent = net.ReadEntity()
  local size = net.ReadUInt(32)
  local data = util.JSONToTable(util.Decompress(net.ReadData(size)))
  ent.PlayersHands = data
  ent.HandRevealSndFin = true
  --ent.WinnerSlot = winnerslot
  local wins = {}
  local winstxt = {}
  for k,v in pairs(data) do
    if v.winner then
      local TheWinner = Player(k)
      wins[#wins + 1] = TheWinner
      winstxt[#winstxt + 1] = TheWinner:Nick()
    end
  end
  if #wins > 1 then
    ent.WinnersTxt = "The Winners are: " .. table.concat(winstxt,", ")
  else
    ent.WinnersTxt = "The Winner is: " .. unpack(winstxt)
  end
  ent.DeckModel:SetPos(ent.DeckOrigin)
  if #wins > 1 then
    local names = ""
    for i = 1,#wins do
      local player = wins[i]
      if i != #wins then
        names = names .. player:Nick() .. ", "
      else
        names = names .. "and " .. player:Nick()
      end
    end
    Poker.ChatRelay(ent, names .. " split the pot!")
  else
    Poker.ChatRelay(ent, unpack(wins):Nick() .. " has taken the pot (" .. ent:GetPot() .. " pts)!")
  end
end )

net.Receive( "Poker_Winner", function()
  local ply = net.ReadEntity()
  local ent = net.ReadEntity()
  local pot = net.ReadInt(32)
  Poker.ChatRelay(ent, ply:Nick() .. " has taken the pot (" .. pot .. " pts)!" )
  ent.Winner = ply
  ent:EmitSound("ambient/levels/canals/windchime2.wav")
end )

local mat_coords = Poker.Textures

local card_back_material = Material("ui/poker/card_back")
local card_joker_material = Material("ui/poker/card_joker")
local render = render
local render_SetMaterial, render_DrawQuadEasy = render.SetMaterial, render.DrawQuadEasy
hook.Add( "PostPlayerDraw", "Poker_Hands_Draw", function(ply)
  if not ply:IsInPoker() then return end
  if ply:HasFolded() then return end
  local ent = ply:GetActivePokerGame()
  if not IsValid(ent) then return end
  local hand = ply:GetPokerHand()
  local boneindex = ply:LookupBone("ValveBiped.Bip01_R_Hand")
  if not boneindex then return end

  local pos, angs = ply:GetBonePosition( boneindex )

  pos = pos + angs:Forward() * 4
  pos = pos + angs:Right() * 6
  pos = pos - angs:Up() * 4
  angs:RotateAroundAxis(angs:Up(), 180)
  local offset = -angs:Right()
  if LocalPlayer() == ply then
    for k,v in pairs(hand) do
      pos = pos - Vector(offset.x , offset.y,0)
      render_SetMaterial( mat_coords[ v.suit .. "_" .. v.rank] )
      render_DrawQuadEasy( pos, angs:Forward(), 3, 4, color_white, 180 )
      render_SetMaterial( card_back_material )
      render_DrawQuadEasy( pos, -angs:Forward(), 3, 4, color_white, 180 )
    end
  else
    for i = 1,5 do
      pos = pos - Vector(offset.x , offset.y,0)
      render_SetMaterial( card_joker_material )
      render_DrawQuadEasy( pos, angs:Forward(), 3, 4, color_white, 180 )
      render_SetMaterial( card_back_material )
      render_DrawQuadEasy( pos, -angs:Forward(), 3, 4, color_white, 180 )
    end
  end

  if not ply:IsPokerTurn() then return end
  if not IsValid(ply) or not ply:Alive() then return end
  local seat = ply:GetVehicle()
  if not IsValid(ent.ArrowModel) then
    ent.ArrowModel = ClientsideModel( "models/phxtended/trieq1x1x1solid.mdl" )
    ent.ArrowModel:SetMaterial("models/weapons/v_slam/new light2")
    ent.ArrowModel:SetModelScale(0.15, 0)
    ent.ArrowModel:DrawShadow(false)
    ent.ArrowModel:SetNoDraw( true )
  end
  local model = ent.ArrowModel
  if not IsValid(seat) or not seat:IsValidVehicle() or not model then return end
  local seatPos = seat:GetPos()
  local seatAng = seat:GetAngles()
  seatPos = seatPos + (seatAng:Up() * 45) - (seatAng:Right() * 5)
  seatAng:RotateAroundAxis(seatAng:Up(),(CurTime() * 30)%360)
  seatAng:RotateAroundAxis(seatAng:Right(),35)
  seatAng:RotateAroundAxis(seatAng:Forward(),45)
  model:SetPos(seatPos)
  model:SetAngles(seatAng)

  model:SetRenderOrigin(seatPos)
  model:SetRenderAngles(seatAng)

  model:DrawModel()

  model:SetRenderOrigin()
  model:SetRenderAngles()
end)
hook.Add( "EntityEmitSound", "Poker_Winning_Sound_Timing", function( t )
  if not IsValid(t.Entity) then return end
  if t.SoundName != "poker/win.wav" then return end
  if t.Entity:GetClass() != "poker_five_card" then return end
	local time = SoundDuration( t.SoundName )
  local TimerName = "Poker_Winning_Sound_Timing" .. t.Entity:EntIndex()
  local Count = math.floor(t.Entity.pot  / time)
  local remainder = Count % 100
  local comp = Count / 100
  local rate = math.floor(time * comp) + remainder
  local amount = 0
  timer.Create(TimerName,( 1 / rate) * (1 / time), time * rate, function()
    if not IsValid(t.Entity) then return end
    t.Entity.pot = math.Approach(t.Entity.pot, 0, rate)
    if amount < 50 then
      for k,v in pairs(t.Entity.PlayersHands) do
        if v.winner then
          t.Entity:ThrowChipToSeat(v.slot)
        end
      end
      amount = amount + 1
    end
    if t.Entity.pot == 0 then timer.Remove(TimerName) end
  end)
  return true
end )
