Poker.ActionPanel = Poker.ActionPanel or nil

surface.CreateFont( "PokerTable3D2DFont", {
	font = "Impact",
	extended = false,
	size = 90,
	weight = 500,
	blursize = 0,
	scanlines = 0,
	antialias = true
} )

surface.CreateFont( "PokerTableUIPanel", {
	font = "Impact",
	extended = false,
	size = 30,
	weight = 500,
	blursize = 0,
	scanlines = 0,
	antialias = true
} )

surface.CreateFont( "PokerTableCredits", {
	font = "Tahoma",
	extended = false,
	size = 65,
	weight = 500,
	blursize = 0,
	scanlines = 0,
	antialias = true
} )

surface.CreateFont( "PokerTableCreditsSub", {
	font = "Tahoma",
	extended = false,
	size = 45,
	weight = 500,
	blursize = 0,
	scanlines = 0,
	antialias = true
} )

local menu_bg
do
  menu_bg = CreateMaterial( "poker_action_menu", "UnlitGeneric", {
        ["$basetexture"] =  "models/gmod_tower/aigik/pokertable",
        ["$basetexturetransform"] = "center .0 .0 scale  0.25 0.35 rotate -90 translate 0.1 0.3",
  } )
end

hook.Add("Think", "Poker_Create_VGUI", function()
	local ply = LocalPlayer()

	if not ply:IsInPoker() or not ply:IsPokerTurn() or ply:HasFolded() then
		if IsValid(Poker.ActionPanel) then
			Poker.ActionPanel:Close()
		end
		return
	end
  local ent = ply:GetActivePokerGame()
  if not IsValid(ent) then return end
  local round = ent:GetRound()
  local bet = ent:GetLastBet()
  if round == POKER_DRAWING or round == POKER_SHOWDOWN then return end

  if Poker.ActionPanel and IsValid(Poker.ActionPanel) then return end
  --if ply.PokerTurnAction then return end
  local ActionPanel = vgui.Create( "DFrame" )
  ActionPanel:SetDraggable(false)
  ActionPanel:SetSize( 320, 450 )
  ActionPanel:SetPos( 100, 450 - ActionPanel:GetTall() / 2 )
  ActionPanel:SetTitle( "" )
  ActionPanel:ShowCloseButton( false )
  --ActionPanel:SetMouseInputEnabled( false )
  --ActionPanel:MouseCapture( false)
	local buttons = {}
	local AmountInPot = ply.AmountInPot or 0
    for i = 1,5 do
      local ActionButton = vgui.Create( "DButton", ActionPanel )
      ActionButton:SetText( Poker.Actions[i] )
      ActionButton:SetFont( "PokerTableUIPanel" )
      ActionButton:SetTextColor( color_white )

      if i == POKER_CHECK and round != POKER_NEXT_BETTING or bet != AmountInPot then
        ActionButton:SetEnabled(false)
        if not Poker.ConfigHasCurrency(ply, bet) then ActionButton:SetEnabled(false) end
      end

      if i == POKER_BET and bet == 0 then
        ActionButton:SetEnabled(true)
        if not Poker.ConfigHasCurrency(ply, bet) then ActionButton:SetEnabled(false) end
      end

      if i == POKER_RAISE and (bet == 0 or ply.PokerTimesRaised >= ent.ConfigRaiseLimit) then
        ActionButton:SetEnabled(false)
      end
      if i == POKER_CALL and bet == 0 then
        ActionButton:SetEnabled(false)
			elseif i == POKER_CALL and bet > AmountInPot then
				ActionButton:SetEnabled(true)
				ActionButton:SetTooltip("Total: " .. bet - AmountInPot )
      end

			if i == POKER_FOLD then
				ActionButton:SetEnabled(true)
			end

      ActionButton:Dock(TOP)
      ActionButton:DockMargin(60, 0, 60, 10)

      ActionButton:SetSize( 250, 30 )
      ActionButton.DoClick = function()
        net.Start("Poker_Player_Action")
        net.WriteInt(i,32)
        if i == POKER_BET or i == POKER_RAISE then
          net.WriteInt(ActionPanel.DermaNumSlider:GetValue(),32)
        end
        net.SendToServer()
      end

      ActionButton.OnCursorEntered = function()
        if not ActionButton:IsEnabled() then return end
        ActionButton:SetTextColor( color_black )
      end
      ActionButton.OnCursorExited = function()
        if not ActionButton:IsEnabled() then return end
        ActionButton:SetTextColor( color_white )
      end
      function ActionButton:Paint(wi, hi)
        if not ActionButton:IsEnabled() then
          draw.RoundedBox( 5, 0, 0, wi, hi, Color(128,0,32,155) )
        else
          draw.RoundedBox( 5, 0, 0, wi, hi, Color(128,0,32,255) )
        end
      end
			buttons[#buttons + 1] = ActionButton
    end

    ActionPanel.DermaNumSlider = vgui.Create( "DNumSlider", ActionPanel )
    ActionPanel.DermaNumSlider:Dock( TOP )
    ActionPanel.DermaNumSlider:DockMargin(20, 0, 20, 10)
		if bet == 0 then
    	ActionPanel.DermaNumSlider:SetText("Bet")
			ActionPanel.DermaNumSlider:SetMin(ent.MinBet)
			ActionPanel.DermaNumSlider:SetMax(ent.MaxBet)
		else
			ActionPanel.DermaNumSlider:SetText("Raise")
			ActionPanel.DermaNumSlider:SetMin(ent.MinBet)
			ActionPanel.DermaNumSlider:SetMax(ent.MaxBet)
		end

		ActionPanel.DermaNumSlider.OnValueChanged = function(slf)
			local InPotThisRound = ply.AmountInPot
			local val = math.Round(slf:GetValue(),0)

			if not buttons[POKER_BET]:IsEnabled() and Poker.ConfigHasCurrency(ply, val) and bet == 0 then
				buttons[POKER_BET]:SetEnabled(true)
			elseif not Poker.ConfigHasCurrency(ply, val) then
				buttons[POKER_BET]:SetEnabled(false)
			end

			if not buttons[POKER_RAISE]:IsEnabled() and bet != 0 and Poker.ConfigHasCurrency(ply, (bet - InPotThisRound) + val) then
				buttons[POKER_RAISE]:SetEnabled(true)
			elseif bet == 0 or not Poker.ConfigHasCurrency(ply, (bet - InPotThisRound) + val) then
				buttons[POKER_RAISE]:SetEnabled(false)
			end

			buttons[POKER_BET]:SetTooltip("Total: " .. val )
			buttons[POKER_RAISE]:SetTooltip("Total: " .. (bet - InPotThisRound) + val )
		end
    ActionPanel.DermaNumSlider:SetDecimals(0)
		ActionPanel.DermaNumSlider:SetValue(1)
    ActionPanel.DermaNumSlider.Label:SetColor(color_white)
    ActionPanel.DermaNumSlider.TextArea:SetTextColor(color_white)
    ActionPanel.DermaNumSlider.Slider.Knob.Paint = function( self, w, h )
      surface.SetDrawColor(255,255,255,255)
      surface.DrawRect(0, 0, w, h)
    end
    ActionPanel.DermaNumSlider.Slider.Paint = function( self, w, h )
      surface.SetDrawColor(0,0,0,255)
      surface.DrawRect(0, 15, w, 3)
    end

    local Money = vgui.Create( "DLabel", ActionPanel )
    Money:Dock( TOP )
    Money:DockMargin(20, 0, 20, 10)
    Money:SetText("Current Money: " .. Poker.ConfigCurrency(ply))
    Money:SetFont("HudHintTextLarge")
    function ActionPanel:Paint(wi,hi)
      surface.SetDrawColor( 255, 255, 255, 255 )
      surface.SetMaterial(menu_bg)
      surface.DrawTexturedRect( 0, 0, wi, hi )
      surface.SetDrawColor( 133, 94, 66, 255 )
      surface.DrawOutlinedRect( 0, 0, wi, hi, 7 )
      surface.SetDrawColor( 103, 54, 66, 255 )
      surface.DrawOutlinedRect( 0, 0, wi, hi, 5 )
    end
    ActionPanel:MakePopup()

    Poker.ActionPanel = ActionPanel
end)
