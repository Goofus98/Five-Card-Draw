LocalPlayer().CurCard =  1
local LastScroll = 0
local LastClick = 0
local hover_eff = {0,0,0,0,0}
local gradient_up = Material("gui/gradient_up")
local Mainfont = "CloseCaption_Bold"
local surface, math, cam, input = surface, math, cam, input
local draw_DrawText = draw.DrawText
local surface_DrawTexturedRectRotated, surface_PlaySound, surface_SetDrawColor, surface_SetMaterial = surface.DrawTexturedRectRotated, surface.PlaySound, surface.SetDrawColor, surface.SetMaterial
local math_sin, math_cos, math_rad, math_Approach, math_Clamp = math.sin, math.cos, math.rad, math.Approach, math.Clamp

local function DrawTexturedRectRotatedPoint( x, y, w, h, rot, x0, y0 )
	local c = math_cos( math_rad( rot ) )
	local s = math_sin( math_rad( rot ) )
	local newx = y0 * s - x0 * c
	local newy = y0 * c + x0 * s

	surface_DrawTexturedRectRotated( x + newx, y + newy, w, h, rot )
end

local NumSelectedCards = 0
hook.Add("StartCommand", "Poker_Card_Selection_Ctrls", function(ply, cmd)
	if not ply:IsInPoker() then return end
	if ply:HasFolded() then return end
	local ent = ply:GetActivePokerGame()
	if not IsValid(ent) then return end

	if ent.PlayersHands then return end
	local delta = cmd:GetMouseWheel()
	if ( delta != 0 ) and (CurTime() - LastScroll) > 0.02 then
		if delta < 0 then
			ply.CurCard = math_Clamp( ply.CurCard - 1, 1, 5 )
		else
			ply.CurCard = math_Clamp( ply.CurCard + 1, 1, 5 )
		end
		surface_PlaySound("poker/hover.wav")
		LastScroll = CurTime()
	end
	if ent:GetRound() != POKER_DRAWING then return end
	if not ply:IsPokerTurn() then return end
	local hovered_card = ply.PokerHand[ply.CurCard]
	local index = hovered_card.suit .. "_" .. hovered_card.rank
	if ( input.WasMousePressed( MOUSE_LEFT ) ) and (CurTime() - LastClick) > 0.02 then
		if ply.SelectedCards[index] then return end
		ply.SelectedCards[index] = true
		NumSelectedCards = math_Clamp( NumSelectedCards + 1, 0, 5 )
		surface_PlaySound("poker/select.wav")
		LastClick = CurTime()
	end

	if ( input.WasMousePressed( MOUSE_RIGHT ) ) and (CurTime() - LastClick) > 0.02 then
		if not ply.SelectedCards[index] then return end
		ply.SelectedCards[index] = nil
		NumSelectedCards = math_Clamp( NumSelectedCards - 1, 0, 5 )
		surface_PlaySound("poker/deselect.wav")
		LastClick = CurTime()
	end

	if ( input.WasMousePressed( MOUSE_MIDDLE ) ) and (CurTime() - LastClick) > 0.02 then
		net.Start("Poker_Hand_Data")
		net.WriteInt(NumSelectedCards, 5)
		net.WriteTable(ply.SelectedCards)
		net.SendToServer()
		NumSelectedCards = 0
		LastClick = CurTime()
	end
	--PrintTable(ply.SelectedCards)
end)

local mat_coords = Poker.Textures

hook.Add( "HUDPaint", "Poker_Card_Selection_Paint", function()
  local ply = LocalPlayer()
  if not ply:IsInPoker() then return end
  if ply:HasFolded() then return end

  local ent = ply:GetActivePokerGame()
  if not IsValid(ent) then return end
  if ent.PlayersHands then return end

  local round = ent:GetRound()
  local IsTurn = ply:IsPokerTurn()
  local w,h = ScrW(), ScrH()
  --card rect size
  local card_x, card_y = w / 11.27, h / 4.55
  local s_x, s_y = w / 2, h / 1.4

  local mat = Matrix()

  mat:Translate(Vector(s_x, h))
  mat:Translate(-Vector(s_x, h))
  cam.PushModelMatrix(mat)
  local Unveil = 30
  local hand = ply:GetPokerHand()
  local hand_eval = ply.HandEval
  if hand then
    if IsTurn and round == POKER_DRAWING then
      draw_DrawText("Left Click to select!", Mainfont, s_x, 0, color_white, TEXT_ALIGN_CENTER)
      draw_DrawText("Right Click to deselect!", Mainfont, s_x, 30, color_white, TEXT_ALIGN_CENTER)
      draw_DrawText("Middle Mouse to confirm!", Mainfont, s_x, 60, color_white, TEXT_ALIGN_CENTER)
    end
    draw_DrawText(hand_eval, Mainfont, s_x, s_y - 40, Color(255,255,255,255), TEXT_ALIGN_CENTER)
    local Uanim = RealFrameTime() + FrameTime() * (1 / 0.55)
    surface_SetDrawColor( color_white )
    for k,v in pairs(hand) do
      local index = v.suit .. "_" .. v.rank
      surface_SetMaterial( mat_coords[index] )

      Unveil = Unveil - ply.PokerHandUnveilAnim
      ply.PokerHandUnveilAnim = math_Approach(ply.PokerHandUnveilAnim, 10, Uanim)

      local p_rot = card_y - s_y
      p_rot = p_rot - hover_eff[k]
      local Tanim = RealFrameTime() * 250
      Tanim = Tanim + FrameTime() * (1 / 4)
      if ply.CurCard == k then
        hover_eff[k] = math_Approach(hover_eff[k], 40, Tanim)
      else
        hover_eff[k] = math_Approach(hover_eff[k], 0, Tanim)
      end
      DrawTexturedRectRotatedPoint( s_x, h + (card_y * 1.7 ), card_x, card_y, Unveil, 0, p_rot )
      if ply.SelectedCards[index] and IsTurn and round == POKER_DRAWING then
        surface_SetMaterial(gradient_up)
        surface_SetDrawColor(255,12,25,155)
        DrawTexturedRectRotatedPoint( s_x, h + (card_y * 1.7 ), card_x, card_y - 13, Unveil, 0, p_rot )
      end
    end
  end
  cam.PopModelMatrix()
end )
