Poker = Poker or {}

Poker.Actions = {
  [1] = "Call",
  [2] = "Bet",
  [3] = "Raise",
  [4] = "Fold",
  [5] = "Check"
}

Poker.HandTypes = {
  [1] = "Four Of A Kind", [10] = "Full House", [9] = "Three Of A Kind", [7] = "Two Pairs",
  [6] = "One Pair", [5] = "High Card", [11] = "Straight", [12] = "Flush", [13] = "Straight Flush",
  [14] = "Royal Flush"
}
Poker.RoundNames = {
  [1] = "Betting", [2] = "Drawing", [3] = "2nd Betting", [4] = "Showdown"
}

Poker.ConfigCurrency = function(ply)
  return ply:PS_GetPoints()
end

Poker.ConfigHasCurrency = function(ply, amount)
  return ply:PS_HasPoints(amount)
end

--ROUND ENUMS
POKER_INITIAL_BETTING	= 1
POKER_DRAWING	= 2
POKER_NEXT_BETTING = 3
POKER_SHOWDOWN	= 4

--ACTIONS ENUMS
POKER_CALL	= 1
POKER_BET	= 2
POKER_RAISE = 3
POKER_FOLD	= 4
POKER_CHECK	= 5

hook.Add( "CalcMainActivity", "Poker_Sitting_Anims", function( ply, vel )
  local seat = ply:GetVehicle()
  local InPoker = ply:IsInPoker()
  if IsValid(ply)  and seat:IsValid() and seat:IsValidVehicle() then
    local act = ply:LookupSequence("drive_jeep")
    local ent = ply:GetActivePokerGame()
    if not IsValid(ent) then return end
    if CLIENT then
      if not ent.HandRevealSndFin then
        local pos = seat:GetPos()
        local ang = seat:GetAngles()
        ply:SetPos(pos - seat:GetForward() * 12 + Vector(0,0,-3))
        ply:SetAngles(ang - Angle(-19,270,0))
        local boneindex = ply:LookupBone("ValveBiped.Bip01_L_Upperarm")
        if boneindex and ply:GetManipulateBoneAngles(boneindex):IsZero() then ply:ManipulateBoneAngles( boneindex, Angle(0,70,0) ) end
      else
        local boneindex = ply:LookupBone("ValveBiped.Bip01_L_Upperarm")
        if boneindex and ply:GetManipulateBoneAngles(boneindex) == Angle(0,70,0) then
          ply:ManipulateBoneAngles( boneindex, Angle(0,0,0)  )
        end
      end
    end
    if ent.HandRevealSndFin then
      act = nil
    end
    return act, act
  elseif IsValid(ply) and not InPoker then
    local boneindex = ply:LookupBone("ValveBiped.Bip01_L_Upperarm")
    if boneindex and ply:GetManipulateBoneAngles(boneindex) == Angle(0,70,0) then
      ply:ManipulateBoneAngles( boneindex, Angle(0,0,0)  )
    end
    return
  end
end )
