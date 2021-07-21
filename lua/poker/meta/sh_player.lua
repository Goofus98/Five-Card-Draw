local Player = FindMetaTable("Player")

function Player:IsInPoker()
  return self:GetNWBool("IsInPoker", false)
end

function Player:HasFolded()
  return self:GetNWBool("PokerHasFolded", false)
end

function Player:IsPokerTurn()
  return self:GetNWBool("IsPokerTurn", false)
end

function Player:GetActivePokerGame()
  return self:GetNWEntity("PokerGame", NULL)
end

function Player:GetPokerHand()
  if CLIENT then
    return self.PokerHand
  else
    return self.PokerHandInstance.Cards
  end
end

function Player:GetPokerHandRank()
  if CLIENT then
    return self.PokerHandRank
  else
    return self.PokerHandInstance.Code
  end
end
