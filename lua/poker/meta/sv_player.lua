local PlyMeta = FindMetaTable("Player")

function PlyMeta:SetIsInPoker(bool)
  if not IsValid(self) then return end
  self:SetNWBool("IsInPoker", bool)
end

--TODO: Not Make this and NWBool
function PlyMeta:SetFolded(bool)
  if not IsValid(self) then return end
  self:SetNWBool("PokerHasFolded", bool)
  if not bool then return end
  local ent = self:GetActivePokerGame()
  if not IsValid(ent) then return end
  ent.ActivePlayers = ent.ActivePlayers - 1
  ent:NextTurn(self)
  self.CanExitPoker = true
  self:ExitVehicle()
end

function PlyMeta:SetActivePokerGame(game)
  if not IsValid(self) then return end
  self:SetNWEntity("PokerGame", game)
end

function PlyMeta:SetPokerHand(hand)
  if not IsValid(self) then return end
  self.PokerHandInstance = hand

  net.Start("Poker_Hand_Data")
  local compressedTbl = util.Compress(util.TableToJSON(hand.Cards))
  local size = compressedTbl:len()
  net.WriteUInt(size, 32)
  net.WriteData(compressedTbl, size)
  net.WriteInt(hand.Code, 5)
  net.Send(self)
end

function PlyMeta:SetPokerTurn(bool)
  if not IsValid(self) then return end
  local ent = self:GetActivePokerGame()
  if not IsValid(ent) then return end
  self:SetNWBool("IsPokerTurn", bool)
  if bool then
    self:SendLua("surface.PlaySound('poker/turn.wav')")
    timer.Create("Poker_Players_Turn" .. ent:EntIndex(), 1, ent.TurnTime + 1, function()
      if not IsValid(ent) then return end
      local reps = timer.RepsLeft("Poker_Players_Turn" .. ent:EntIndex())
      ent:SetTurnTimeLeft(reps)
      if reps == 0 then
        if ent:GetRound() != POKER_DRAWING then
          self:SetFolded(true)
        else
          ent:NextTurn(self)
        end
      end
    end)
  end
end

function PlyMeta:GetPokerHandStrength()
  if not IsValid(self) then return end
  return self.PokerHandInstance:GetStrength()
end

function PlyMeta:GetPokerHandInRanks()
  if not IsValid(self) then return end
  return self.PokerHandInstance:Transform()
end
