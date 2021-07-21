AddCSLuaFile()

DEFINE_BASECLASS( "base_anim" )

ENT.PrintName = "Five Card Draw"
ENT.Author = "Goofus"
ENT.Category = "Fun + Games"

ENT.Editable = false
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

--Game Configs
ENT.MinAntee = 5000
ENT.MaxAntee = 100000
ENT.MinBet = 1000
ENT.MaxBet = 15000
--for host
ENT.AutoKickTime = 20
--waiting for players to join
ENT.WaitingTime = 15
ENT.TurnTime = 30
--how many times a player can raise per betting round
ENT.ConfigRaiseLimit = 3

--in case of shutdown while a game is active
if SERVER then
  ENT.CurrencyLog = {}
  ENT.BettingLog = {}
  ENT.Deck = {}
  ENT.Seats = {}
  ENT.Players = {}
  ENT.PokerChips = {}
  ENT.ActivePlayers = 0
  ENT.Winners = nil
end

ENT.SeatPositions = {}
ENT.HandRevealSndFin = false

function ENT:SpawnFunction( ply, tr, ClassName )
  if ( not tr.Hit ) then return end

  local ang = ply:EyeAngles()
	ang.yaw = ang.yaw
	ang.roll = 0
	ang.pitch = 0

	local ent = ents.Create( ClassName )
	ent:SetPos( tr.HitPos + tr.HitNormal )
  ent:SetAngles( ang )
	ent:Spawn()
	ent:Activate()

	return ent
end

function ENT:SetupDataTables()
  self:NetworkVar( "Bool", 0, "Playing" )
  self:NetworkVar( "Entity", 0, "Host" )
  self:NetworkVar( "Int", 0, "Round" )
  self:NetworkVar( "Int", 1, "Pot" )
  self:NetworkVar( "Int", 2, "Antee" )
  self:NetworkVar( "Int", 3, "LastBet" )
  self:NetworkVar( "Int", 4, "TimeLeft" )
  self:NetworkVar( "Int", 5, "TurnTimeLeft" )
	if ( SERVER ) then
		self:NetworkVarNotify( "Playing", self.GameCommence )
    self:NetworkVarNotify( "Round", self.RoundChange )
    self:NetworkVarNotify( "Host", self.HostChange )
    self:NetworkVarNotify( "Antee", self.NewGameMade )
    self:NetworkVarNotify( "Pot", self.PotIncrease )
	end
end

if SERVER then
  function ENT:ConfigTakeCurrency(ply,amount)
    local id = ply:AccountID()
    local uid = ply:UserID()
    local round = self:GetRound()
    if not self.CurrencyLog[id] then return end
    self.CurrencyLog[id] = self.CurrencyLog[id] + amount
    if round == POKER_INITIAL_BETTING or round == POKER_NEXT_BETTING then
      if not self.BettingLog[uid] then return end
      self.BettingLog[uid] = self.BettingLog[uid] + amount
    end
    Poker.ConfigTakeCurrency(ply, amount)
    self:SetPot(self:GetPot() + amount)
  end

  function ENT:ResetDataTables()
    self:SetPlaying(false)
    for k,_ in pairs(self.Players) do
      local v = Player(k)
      if IsValid(v) then
        v.CanExitPoker = true
        --v:SetPokerTurn(false)
        v:ExitVehicle()
      end
    end
    for _,v in pairs(self.PokerChips) do
      if not v:GetNoDraw() then
        v:SetNoDraw(true)
        v:SetFlexWeight(0, 0)
      end
    end
    self:SetRound(0)
    self:SetPot(0)
    self:SetHost(NULL)
    self:SetAntee(0)
    self:SetLastBet(0)
    self:SetTimeLeft(0)
    self:SetTurnTimeLeft(0)
    self.Winners = nil
    self.BettingLog = {}
    self.CurrencyLog = {}
    self.Players = {}
    self.ActivePlayers = 0
    self.HandRevealSndFin = false
  end

  function ENT:PotIncrease(_, _, PotAmt)
    if PotAmt == 0 then return end
    local maxCount = math.floor(PotAmt / 1000)
    local comp = maxCount / 100
    local remainder = maxCount % 100
    for i = 1, #self.PokerChips do
      local stack = self.PokerChips[i]
      if stack:GetFlexWeight(0) >= 100 then goto next end
      if comp >= i then
        stack:SetNoDraw(false)
        stack:SetFlexWeight(0, 100)
      elseif comp > i - 1 then
        stack:SetNoDraw(false)
        stack:SetFlexWeight(0, remainder)
        return
      end
      ::next::
    end
  end
end

function ENT:NewGameMade(_, _, antee)
  local host = self:GetHost()
  if antee <= 0 then return end
  if not IsValid(host) then return end
  host:SetIsInPoker(true)
  host.CanExitPoker = false
  self.Winners = nil
  timer.Create("Poker_Waiting_For_Plys" .. self:EntIndex(), 1, self.WaitingTime + 1, function()
    local reps = timer.RepsLeft("Poker_Waiting_For_Plys" .. self:EntIndex())
    if not IsValid(self) or not IsValid(self:GetHost()) then return end
    self:SetTimeLeft(reps)
    if reps == 0 then
      if self.ActivePlayers == 1 then
        host:ChatPrint("No one wanted to play :(")
        host.CanExitPoker = true
        host:ExitVehicle()
      else
        self:SetPlaying(true)
      end
    end
  end)
end

function ENT:HostChange(_, _, ply)
  if not IsValid(ply) then return end
  net.Start("Poker_Host_Settings")
  net.WriteEntity(self)
  net.Send(ply)

  timer.Create("Poker_Host_Decide_Time" .. self:EntIndex(), self.AutoKickTime, 1,function()
    if not IsValid(ply) then return end
    ply.CanExitPoker = true
    ply:ExitVehicle()
  end)
end

function ENT:RoundChange(_, _, round)
  if round == 0 then return end
  if timer.Exists("Poker_Players_Turn" .. self:EntIndex()) then
    timer.Remove("Poker_Players_Turn" .. self:EntIndex())
  end
  if self.ActivePlayers == 0 then return end
  self.LastPlayerReached = false

  if round == POKER_SHOWDOWN then
    local winner = self:GetWinner()
    if winner then
      self:SetWinner(winner, false)
    end
    return
  end
  if round == POKER_NEXT_BETTING then
    self:SetLastBet(0)
    for k,_ in pairs(self.Players) do
      local v = Player(k)
      if IsValid(v) and not v:HasFolded() then
        self.BettingLog[v:UserID()] = 0
        v.PokerTimesRaised = 0
        v:SendLua([[
        LocalPlayer().PokerTimesRaised = 0
        LocalPlayer().AmountInPot = 0
        ]])
      end
    end
  end
  local sortedPlayers = table.SortByKey( self.Players )
  for i = 1, #sortedPlayers do
    local player = Player(sortedPlayers[i])
    if IsValid(player) then
      player:SetPokerTurn(true)
      return
    end
  end
end

function ENT:GameCommence( _, _, new )
  if not new then return end

  if timer.Exists( "Poker_Host_Decide_Time" .. self:EntIndex() ) then
    timer.Remove( "Poker_Host_Decide_Time" .. self:EntIndex() )
  end
  self.Deck = Deck.Create()
  for k,_ in pairs(self.Players) do
    local v = Player(k)
    if IsValid(v) and Poker.ConfigHasCurrency(v, self:GetAntee()) then
      if not self.CurrencyLog[v:AccountID()] then
        self.CurrencyLog[v:AccountID()] = 0
      end
      if not self.BettingLog[v:UserID()] then
        self.BettingLog[v:UserID()] = 0
      end
      v:SetIsInPoker(true)
      v:SetFolded(false)
      v:SetActivePokerGame(self)
      v.CanExitPoker = false
      v.PokerTimesRaised = 0
      local hand = Hand.Create(self.Deck)
      v:SetPokerHand(hand)
      self:ConfigTakeCurrency(v, self:GetAntee())
    elseif IsValid(v) then
      self.ActivePlayers = self.ActivePlayers - 1
      v:ExitVehicle()
    end
  end
  if self.ActivePlayers == 0 then return end

  net.Start("Poker_Game_Start")
  net.WriteInt(self.ActivePlayers, 5)
  net.WriteEntity(self)
  net.Broadcast()
  self:SetRound(POKER_INITIAL_BETTING)
end

function ENT:Initialize()
  local pos = self:GetPos()
  local ang = self:GetAngles()
  local up = self:GetUp()
  local forward = self:GetForward()
  local right = self:GetRight()
  local maxs = select( 2, self:GetModelBounds() )
  local angles = self:GetAngles()
  local center = pos + Vector( 0, 0, maxs.z - 0.9 ) + forward * 12

  if CLIENT then
    --card anims
    self.deck_anim = 0
    self.Danim = nil
    self.Prot_x = -65
    self.Prot_y = 90

    self.pot = -1
    self.ArrowModel = ClientsideModel( "models/phxtended/trieq1x1x1solid.mdl" )
    self.ArrowModel:SetMaterial("models/weapons/v_slam/new light2")
    self.ArrowModel:SetModelScale(0.15, 0)
    self.ArrowModel:DrawShadow(false)
    self.ArrowModel:SetNoDraw( true )

    --Deck model anim
    self.DeckAnim = 1.4
    self.DeckOrigin = center + forward * 13 - Vector(0,0,1.35)
    self.DeckModel = ClientsideModel( "models/goofus/poker/poker_deck.mdl")
    self.DeckModel:SetPos(self.DeckOrigin)
    self.DeckModel:SetAngles(angles - Angle(0,90,0))
    self.DeckModel:SetModelScale(0.15)
    self.DeckModel:DrawShadow(false)
    self.DeckModel:SetNoDraw(true)

    self.PlayThrowChipsToSeatAnim = {}
    self.PlayThrowCardsAnim = {}
    self.SeatBeziers = {}

    local RMins, RMaxs = self:GetRenderBounds()
    self:SetRenderBounds(RMins + Vector(-50,0,0), RMaxs + Vector(0,0,65))
  end

  for i = 1,4 do
    local offset = (right * 40 * (i - 2.5) ) - (forward * 63)
    local seat_pos = pos + offset
    self.SeatPositions[#self.SeatPositions + 1] = seat_pos
    if CLIENT then
      local dir = (center - seat_pos):GetNormalized()
      local points = {
        seat_pos, seat_pos + dir * 24 + up * 10,
        seat_pos + dir * 48 + up * 20, seat_pos + dir * 62 + up * 40,
        seat_pos + dir * 86 + up * 20, seat_pos + dir * 100,
        center
      }
      self.SeatBeziers[#self.SeatBeziers + 1] = points
    end
  end

  if ( CLIENT ) then return end

	self:SetModel( "models/gmod_tower/aigik/pokertable.mdl" )
  self:PhysicsInit( SOLID_VPHYSICS )
  self:SetMoveType( MOVETYPE_NONE )
  self:SetCollisionGroup( COLLISION_GROUP_NONE )
  local table_phys = self:GetPhysicsObject()
  if IsValid(table_phys) then
    table_phys:EnableMotion(false)
  end

  for i = 1,4 do
    local player_seat_mesh = ents.Create( "prop_dynamic" )
    player_seat_mesh:SetModel( "models/gmod_tower/aigik/casino_stool.mdl" )
    --player_seat_mesh:SetKeyValue("disableshadows",1)
    player_seat_mesh:SetAngles( ang )
    player_seat_mesh:SetPos( self.SeatPositions[i] )
    player_seat_mesh:Spawn()
    local seat_phys = player_seat_mesh:GetPhysicsObject()
  	if IsValid(seat_phys) then
      seat_phys:Wake()
  		seat_phys:EnableMotion(false)
  	end

    local player_seat = ents.Create( "prop_vehicle_prisoner_pod" )
    player_seat:SetModel( "models/nova/airboat_seat.mdl" )
    player_seat:SetKeyValue("vehiclescript","scripts/vehicles/prisoner_pod.txt")
    --player_seat:SetKeyValue("disableshadows",1)
    player_seat:SetPos( self.SeatPositions[i] + Vector(0,0,30) )
    player_seat:SetAngles( ang - Angle(0,90,0))
    player_seat:SetMoveType( MOVETYPE_NONE )
    player_seat:SetRenderMode( RENDERMODE_ENVIROMENTAL )
    player_seat:SetParent(player_seat_mesh)
    player_seat:Spawn()
    --fixed jank parented physics?

    player_seat:PhysicsInitStatic( SOLID_VPHYSICS )
    --player_seat:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
    seat_phys = player_seat:GetPhysicsObject()

    if IsValid(seat_phys) then
      seat_phys:Wake()
      seat_phys:EnableMotion(false)
    end
    player_seat:Activate()
    player_seat.PokerSeat = true
    player_seat.PlayerSlot = i
    player_seat:SetNWEntity( "PokerGame", self )
    self.Seats[#self.Seats + 1] = player_seat_mesh
  end
  local maxs = select( 2, self:GetModelBounds() )
  local angles = self:GetAngles()
  local center = pos + Vector( 0, 0, maxs.z - 0.9 ) + ang:Forward() * 12
  for i = 1,8 do
    angles:RotateAroundAxis(-angles:Up(), 45)
    center = center + angles:Forward() * 4 + angles:Right() * 4
    local player_chip_stack = ents.Create( "prop_dynamic" )
    player_chip_stack:SetModel( "models/goofus/poker/poker_chip.mdl" )
    player_chip_stack:SetPos( center )
    player_chip_stack:SetAngles( ang - Angle(0, 180,0) )
    player_chip_stack:SetModelScale( 0.3 )
    player_chip_stack:SetFlexWeight(0, 30)
    player_chip_stack:SetParent(self, i)
    player_chip_stack:Spawn()
    player_chip_stack:SetNoDraw(true)
    player_chip_stack:SetMoveType( MOVETYPE_NONE )
    player_chip_stack:SetCollisionGroup( COLLISION_GROUP_NONE )
    self.PokerChips[#self.PokerChips + 1] = player_chip_stack
  end

  for i = 1,4 do
    local offset = (right * 40 * (i - 2.5) ) - (forward * 23) + (up * 39.15)
    local stack_pos = Vector(0,0,0)
    local player_chip_stack = ents.Create( "prop_dynamic" )
    player_chip_stack:SetModel( "models/goofus/poker/poker_chip.mdl" )
    player_chip_stack:SetPos( pos + offset + stack_pos )
    player_chip_stack:SetAngles( ang - Angle(0, 180,0) )
    player_chip_stack:SetModelScale( 0.3 )
    player_chip_stack:SetFlexWeight(0, 13)
    player_chip_stack:SetParent(self)
    player_chip_stack:Spawn()
    player_chip_stack:SetMoveType( MOVETYPE_NONE )
    player_chip_stack:SetCollisionGroup( COLLISION_GROUP_NONE )
    stack_pos = stack_pos + Vector(0,34,0)
  end
end

function ENT:OnRemove()
  if SERVER then
    for k = 1, #self.Seats do
      if IsValid( self.Seats[k] ) then
         self.Seats[k]:Remove()
      end
    end
  else
    if IsValid(self.ArrowModel) and IsValid(self.DeckModel) then
      self.ArrowModel:Remove()
      self.DeckModel:Remove()
    end
  end
end

if SERVER then
  --First check who has the strongest hand tier
  function ENT:GetWinner()
    local same_hands = {}
    for id,SeatID in pairs(self.Players) do
      local ply = Player(id)
      if IsValid(ply) and not ply:HasFolded() then
        local strength = ply:GetPokerHandStrength()
        if not same_hands[strength] then
          same_hands[strength] = {{ID = id}}
        else
          table.insert(same_hands[strength], {ID = id})
        end
      end
    end
    local highest = table.maxn(same_hands)
    local SameHandCount = #same_hands[highest]

    if SameHandCount > 1 then
      --More than 1 player have same hand type so we calculate a hand strength value for them
      local HandsToAnalyze = {}
      for i = 1, SameHandCount do
        local tbl = same_hands[highest][i]
        local ply = Player(tbl.ID)
        if IsValid(ply) and not ply:HasFolded() then
          HandsToAnalyze[tbl.ID] = ply:GetPokerHandInRanks()
        end
      end
      return Poker.CalculateStrongestHand(HandsToAnalyze)
    else
      return {unpack(same_hands[highest]).ID}
    end
  end

  --ply is an array of userIDs
  function ENT:SetWinner(ply, ByDefault)
    if not ply then return end
    if ByDefault then
      local winner = Player(ply)
      local pot = self:GetPot()
      net.Start("Poker_Winner")
      net.WriteEntity(winner)
      net.WriteEntity(self)
      net.WriteInt(pot, 32)
      net.Broadcast()
      if timer.Exists("Poker_Players_Turn" .. self:EntIndex()) then
        timer.Remove("Poker_Players_Turn" .. self:EntIndex())
      end
      Poker.ConfigGiveCurrency(winner, pot)
      self:ResetDataTables()
    else
      local Winners = {}
      for i = 1,#ply do
        local id = ply[i]
        Winners[id] = true
      end
      self.Winners = Winners
      self.WinnerCount = #ply
      self:EmitSound("gmodtower/casino/poker_reveal.mp3")
    end
  end

  function ENT:CheckForWinner()
    if self.ActivePlayers == 1 then
      for k,_ in pairs(self.Players) do
        local v = Player(k)
        if IsValid(v) and not v:HasFolded() then
          self:SetWinner(k, true)
          return true
        end
      end
    end
    return false
  end

  function ENT:NextTurn(LastPly)
    if self.ActivePlayers == 0 then return end
    local round = self:GetRound()
    if timer.Exists("Poker_Players_Turn" .. self:EntIndex()) then
      timer.Remove("Poker_Players_Turn" .. self:EntIndex())
    end
    LastPly:SetPokerTurn(false)

    if self:CheckForWinner() then return end

    local sortedPlayers = table.SortByKey( self.Players )
    --PrintTable(sortedPlayers)
    if not self.LastPlayerReached then
      for i = 1, #sortedPlayers do
        local player = Player(sortedPlayers[i])
        --the last player before round change
        if LastPly == player and not next(sortedPlayers, i) then
          self.LastPlayerReached = true
          break
        elseif LastPly == player then
          for k = i + 1, #sortedPlayers do
            local NextPlayer = Player(sortedPlayers[k])
            if IsValid(NextPlayer) and not NextPlayer:HasFolded() then
              NextPlayer:SetPokerTurn(true)
              return
            end
          end
        end
      end
    end
    if self.LastPlayerReached then
      if (round == POKER_DRAWING) then goto NEXTROUND end
      for k = 1, #sortedPlayers do
        local ScannedPlayer = Player(sortedPlayers[k])
        if IsValid(ScannedPlayer) and self.BettingLog[ScannedPlayer:UserID()] < self:GetLastBet() and not ScannedPlayer:HasFolded() then
          ScannedPlayer:SetPokerTurn(true)
          return
        end
      end
      ::NEXTROUND::
      self:NextRound()
    end
  end

  function ENT:NextRound()
    local round = self:GetRound()
    self:SetRound(round + 1)
  end
end

function ENT:Think()
    self:NextThink(CurTime())

    if SERVER then
      if self.ActivePlayers == 0 and self:GetPlaying() then
        self:ResetDataTables()
      end
      if self.ActivePlayers == 0 and self:GetAntee() != 0 then
        self:SetAntee(0)
        self:SetTimeLeft(0)
      end
    end
    return true
end

if ( SERVER ) then return end

function ENT:ThrowFromSeat(id, amt, IsCard)
  self.PlayThrowCardsAnim[#self.PlayThrowCardsAnim + 1] = {
    finished = false,
    slot = id,
    rate = {},
    sndPlayed = {},
    IsCard = IsCard
  }
  for i = 1,amt do
    self.PlayThrowCardsAnim[#self.PlayThrowCardsAnim].rate[i] = 0
    self.PlayThrowCardsAnim[#self.PlayThrowCardsAnim].sndPlayed[i] = false
  end
end
function ENT:ThrowChipToSeat(id)
  self.PlayThrowChipsToSeatAnim[#self.PlayThrowChipsToSeatAnim + 1] = {
    finished = false,
    slot = id,
    rate = 1,
    sndPlayed = false }
end

local pot_area = Material("decals/light")
local test_material = Material("ui/poker/coin_top_draw")
local card_back_material = Material("ui/poker/card_back")
local chipSnd, cardSnd = "gmodtower/casino/chip.wav", "poker/draw.wav"
local surface, render, cam, math, draw = surface, render, cam, math, draw
local draw_SimpleText = draw.SimpleText
local surface_DrawTexturedRectRotated, surface_SetFont, surface_DrawRect, surface_GetTextSize, surface_SetDrawColor, surface_DrawOutlinedRect, surface_SetMaterial = surface.DrawTexturedRectRotated, surface.SetFont, surface.DrawRect, surface.GetTextSize, surface.SetDrawColor, surface.DrawOutlinedRect, surface.SetMaterial
local math_sin, math_cos, math_rad, math_Round, math_min, math_Approach, math_random, math_BSplinePoint = math.sin, math.cos, math.rad, math.Round, math.min, math.Approach, math.random, math.BSplinePoint
local R_SetMat, R_DrawQuad, R_OvrDepth, R_DepthRange = render.SetMaterial, render.DrawQuadEasy, render.OverrideDepthEnable, render.DepthRange
local Cam_Start3D2D, Cam_End3D2D = cam.Start3D2D, cam.End3D2D
local mat_coords, HTypes, P_Rounds = Poker.Textures, Poker.HandTypes, Poker.RoundNames
local PokerFont, CreditsFont, SubCreditsFont, HandFont = "PokerTable3D2DFont", "PokerTableCredits", "PokerTableCreditsSub", "CloseCaption_Bold"
local Credits, CreditsSub = "Coded by Goofus", "Dedicated to a friend!"

local function DrawTexturedRectRotatedPoint( x, y, w, h, rot, x0, y0 )
  local c = math_cos( math_rad( rot ) )
  local s = math_sin( math_rad( rot ) )

  local newx = y0 * s - x0 * c
  local newy = y0 * c + x0 * s

  surface_DrawTexturedRectRotated( x + newx, y + newy, w, h, rot )
end

function ENT:Draw()
  self:DrawModel()
  --https://github.com/Facepunch/garrysmod-issues/issues/3184
  if not IsValid(self.DeckModel) then
    self.DeckModel = ClientsideModel( "models/goofus/poker/poker_deck.mdl", RENDERGROUP_TRANSLUCENT)
    self.DeckModel:SetPos(self.DeckOrigin)
    self.DeckModel:SetAngles(self:GetAngles() - Angle(0,90,0))
    self.DeckModel:SetModelScale(0.25)
    self.DeckModel:DrawShadow(false)
    self.DeckModel:SetNoDraw(true)
  end
  self.DeckModel:DrawModel()
end

function ENT:DrawTranslucent()
  local fsin = math_sin(CurTime() * 1.2) * 2
  local maxs = select( 2, self:GetModelBounds() )
  local forward = self:GetForward()
  local right = self:GetRight()
  local pos = self:GetPos() + Vector( 0, 0, maxs.z - 0.9 ) + forward * 5
  local angle = self:GetAngles()
  local QuadRot = angle.y

  local ply = LocalPlayer()
  local ply_angs = ply:EyeAngles()
  local GameText = self.PrintName

  if ply:InVehicle() then
    ply_angs = angle - Angle(0,90,0)
  else
    ply_angs:RotateAroundAxis(ply_angs:Up(), -90)
  end
  R_SetMat( pot_area )
  R_DrawQuad( pos, Vector(0, 0, 1), 50, 50, color_white, 0 )

  local deg = 25
  Cam_Start3D2D(pos - Vector(0,0,2.7), Angle(180, QuadRot - 90, 0) , 0.1)
    draw_SimpleText(Credits,CreditsFont,0, -155,color_black,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    draw_SimpleText(CreditsSub,SubCreditsFont, 0, -95,color_black,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
  Cam_End3D2D()

  R_OvrDepth( true, true )
    Cam_Start3D2D(pos + Vector(0, 0, -5 + fsin  + 50), Angle(0, ply_angs.y, 90) , 0.1)
    R_DepthRange(0.02,1)
      local MoneyText = "Antee: " .. self:GetAntee() .. " pts"
      local TimeText = ""
      local IsPlaying = self:GetPlaying()
      if IsPlaying and not self.PlayersHands then
        MoneyText = "Current pot: " .. self:GetPot() .. " pts"
      elseif IsPlaying then
        if self.pot == -1 then
          self.pot = self:GetPot()
          self:EmitSound("poker/win.wav")
        end
        MoneyText = "Current pot: " .. self.pot .. " pts"
      end
      surface_SetFont(PokerFont)
      local txtW, txtH = surface_GetTextSize(GameText)
      surface_SetDrawColor(0,0,0,215)
      surface_DrawRect((-txtW / 2) - 10, -180, txtW + 20, txtH)

      txtW, txtH = surface_GetTextSize(MoneyText)
      surface_DrawRect((-txtW / 2) - 10, -90, txtW + 20, txtH)
      local TimeLeft = self:GetTimeLeft()
      if TimeLeft != 0 then
        TimeText = "Match Starting: " .. TimeLeft
        txtW, txtH = surface_GetTextSize(TimeText)
        surface_DrawRect((-txtW / 2) - 10, 0, txtW + 20, txtH)
      end
      local round = self:GetRound()
      local TurnTime = self:GetTurnTimeLeft()
      if round != 0 and TurnTime != 0 then
        if round != 4 then
          TimeText = P_Rounds[round] .. "|" .. TurnTime
        else
          TimeText = P_Rounds[round]
        end
        txtW, txtH = surface_GetTextSize(TimeText)
        surface_DrawRect((-txtW / 2) - 10, 0, txtW + 20, txtH)
      end

      if self.WinnersTxt then
        txtW, txtH = surface_GetTextSize(self.WinnersTxt)
        surface_DrawRect((-txtW / 2) - 10, 90, txtW + 20, txtH)
      end
      R_DepthRange(0.01,1)
      draw_SimpleText(GameText,PokerFont,0, -180,color_white,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
      draw_SimpleText(MoneyText,PokerFont,0,-90,color_white,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
      if self:GetTimeLeft() != 0 then
        draw_SimpleText(TimeText,PokerFont,0,0,color_white,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
      end
      if round != 0 and self:GetTurnTimeLeft() != 0 then
        draw_SimpleText(TimeText,PokerFont,0,0,color_white,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
      end

      if self.WinnersTxt then
        draw_SimpleText(self.WinnersTxt ,PokerFont,0, 90,color_white,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
      end
    Cam_End3D2D()
  R_OvrDepth( false )
  R_DepthRange(0,1)

  pos = pos + forward * 27
  angle = angle + Angle(0,-73,0)
  if self.Danim and not self.FinishedDeckAnim then
    local DeckReachedTarget = self.DeckModel:GetPos().z <= (self:GetPos() + Vector( 0, 0, maxs.z  )).z
    Cam_Start3D2D( pos, angle, 0.5 )
      surface_SetDrawColor( 255, 255, 255, 170 )
      surface_DrawOutlinedRect( 89, 51, 14, 19, 1 )
      local count = 0
      for k,v in pairs(mat_coords) do
        surface_SetMaterial(v)
        deg = deg - self.deck_anim
        count = count + 1
        self.FrameDelta = (CurTime() - self.Danim) / (count * 100)
        self.FrameDelta = self.FrameDelta + FrameTime() * ( 1 / 10000)
        if self.FrameDelta > 1 then
          self.FrameDelta = math_min(1, self.FrameDelta - 1)
        end
        self.deck_anim = Lerp(self.FrameDelta, self.deck_anim, 3)

        if math_Round(self.deck_anim) == 3 then
          self.Prot_x = Lerp(self.FrameDelta, self.Prot_x, 0)
          self.Prot_y = Lerp(self.FrameDelta, self.Prot_y, 0)
          self.DeckAnim = Lerp(self.FrameDelta, self.DeckAnim, -1.3)
          if DeckReachedTarget then
            local DeckPos = self.DeckModel:GetPos() + Vector(0,0,0.001)
            self.DeckModel:SetPos(DeckPos)
            self.DeckModel:SetRenderOrigin(DeckPos)
          end
        end
        if DeckReachedTarget then
          DrawTexturedRectRotatedPoint( 0, 3 , 11, 16, deg, self.Prot_x, self.Prot_y )
        else
          self.FinishedDeckAnim = true
          break
        end
      end
    Cam_End3D2D()
  end

  if self.PlayersHands then
    for k,v in pairs(self.PlayersHands) do
      local HandPos = self.SeatPositions[v.slot] + Vector(0, 0, maxs.z + 0.2) + forward * 35
      local HandType = HTypes[v.rank]
      for i = 5, 1, -1 do
        local off = ((-right * 3) * i) + (right * 10)
        local card = v.hand[i]
        R_SetMat(mat_coords[card.suit .. "_" .. card.rank])
        R_DrawQuad(HandPos + off, Vector(0,0,1), 3, 4, color_white, QuadRot)
      end
      R_OvrDepth( true, true )
      Cam_Start3D2D(HandPos + Vector(0,0,1), Angle(0, ply_angs.y, 90) , 0.1)
        draw_SimpleText(HandType,HandFont,0,-90,color_white,TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
      Cam_End3D2D()
      R_OvrDepth( false )
    end
  end

  if next(self.PlayThrowChipsToSeatAnim) != nil then
    for k,v in pairs(self.PlayThrowChipsToSeatAnim) do
      if v.finished then goto next end
      v.rate =  math_Approach(v.rate, 0, (RealFrameTime() * 1.5) + FrameTime() * (1 / 4))
      local p = math_BSplinePoint( v.rate, self.SeatBeziers[v.slot], 1 )
      if v.rate > 0 and v.rate < 0.1 and not v.sndPlayed then
        self:EmitSound( chipSnd, 75, math_random(90, 155) )
        v.sndPlayed = true
        v.finished = true
        break
      end
      if v.rate != 0 then
        R_SetMat( test_material )
        R_DrawQuad( p, Vector(0,0, 1), 4, 4, color_white, QuadRot )
      end
      ::next::
    end
  end

  if next(self.PlayThrowCardsAnim) != nil then
    for k = 1, #self.PlayThrowCardsAnim do
      local v = self.PlayThrowCardsAnim[k]
      if v.finished then goto next end
      local done = 0
      for i = 1,#v.rate do
        v.rate[i] =  math_Approach(v.rate[i], 1, ((RealFrameTime() * 1.25) + FrameTime() * (1 / 2)) / i)
        local p = math_BSplinePoint( v.rate[i], self.SeatBeziers[v.slot], 1 )
        if v.rate[i] < 1 and v.rate[i] > 0.9 and not v.sndPlayed[i] then
          if v.IsCard then
            self:EmitSound( cardSnd, 75, math_random(90, 155) )
          else
            self:EmitSound( chipSnd, 75, math_random(90, 155) )
          end
          v.sndPlayed[i] = true
          done = done + 1
        end
        if v.rate[i] != 1 then
          if v.IsCard then
            R_SetMat( card_back_material )
          else
            R_SetMat( test_material )
          end
          R_DrawQuad( p, Vector(0,0, 1), 4, 4, color_white, QuadRot )
        end
      end
      if done == 5 then v.finished = true end
      ::next::
    end
  end
end
