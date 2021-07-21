Hand = {}

local bit = bit
local bit_and = bit.band
local HandTiers = {
  [1] = 8, [10] = 7, [9] = 4, [7] = 3,
  [6] = 2, [5] = 1, [11] = 5, [12] = 6,
  [13] = 9, [14] = 10
}
local HAND  = {
  __tonumber = function(self)
    return self.Code
  end
}

HAND.__index = HAND
HAND.Deck = nil
HAND.Code = 0
HAND.Strength = 0

--Algorithm Credit: https://jonathanhsiao.com/blog/evaluating-poker-hands-with-bit-math
local function GetCode(hand)
  local Hand_Bitfield_1 = ""
  local bits1 = {[1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0,
  [7] = 0, [8] = 0, [9] = 0, [10] = 0, [11] = 0, [12] = 0, [13] = 0 }
  local bits2 = {}
  local same_suits = 0

  for k,v in pairs(hand) do
    local rank = v.rank
    local suit = v.suit
    if bits1[rank] == 0 then bits1[rank] = 1 end
    if suit == hand[1].suit then same_suits = same_suits + 1 end

    local Curbit = bits2[rank] or 0
    bits2[rank] = Curbit + (Curbit + 1)
  end
  same_suits = (same_suits == 5)

  --workaround since lua loses precision past 53 bits
  local hand_code = 0
  for _,v in pairs(bits2) do
    hand_code = hand_code + (v % 15)
  end

  for i = 13,1,-1 do
    Hand_Bitfield_1 = Hand_Bitfield_1 .. bits1[i]
  end
  Hand_Bitfield_1 = tonumber( Hand_Bitfield_1 .. "00", 2 )

  if same_suits then
    if Hand_Bitfield_1 == 31744 then
      return 14
    elseif hand_code == 5 then
      local val = bit_and(Hand_Bitfield_1, -Hand_Bitfield_1)
      Hand_Bitfield_1 = Hand_Bitfield_1 / val
      if Hand_Bitfield_1 == 31 then
        return 13
      else
        return 12
      end
    end
  elseif hand_code == 5 then
    local val = bit_and(Hand_Bitfield_1, -Hand_Bitfield_1)
    Hand_Bitfield_1 = Hand_Bitfield_1 / val
    if Hand_Bitfield_1 == 31 then
      return 11
    end
  end

  return hand_code
end

debug.getregistry().Hand = HAND

function Hand.Create(deck)
  local hand = {}
  hand.Cards = deck:PopCards(5)
  hand.Code = GetCode(hand.Cards)
  hand.Strength = HandTiers[hand.Code]
  hand.Deck = deck
  local ret = setmetatable(hand, HAND)

  return ret
end

function HAND:Validate(cards, amount)
  local found = 0
  for i = 1,5 do
    local card = self.Cards[i]
    local index = card.suit .. "_" .. card.rank
    if cards[index] then
      found = found + 1
    end
  end
  return found == amount
end

function HAND:Discard(cards, amount)
  if not self:Validate(cards, amount) then return false end
  if #self.Deck < amount then return false end
  local NewCards = self.Deck:PopCards(amount)

  for i = 1,5 do
    local card = self.Cards[i]
    if cards[card.suit .. "_" .. card.rank] then
      self.Cards[i] = NewCards[#NewCards]
      NewCards[#NewCards] = nil
    end
  end
  self.Code = GetCode(self.Cards)
  self.Strength = HandTiers[self.Code]
  return true
end

--sort by pairs then by rank value returns a sequential table of sorted numbers
--can also be used to get kicker (not implemented in this addon)
function HAND:Transform()
  local SortedHand = {}
  local occurence = {}
  local set = {}

  for i = 1,#self.Cards do
    local card = self.Cards[i]
    occurence[card.rank] = ( occurence[card.rank] or 0 ) + 1
  end

  for rank,occur in pairs(occurence) do
    if not set[occur] then set[occur] = {} end
    for i = 1, occur do
      set[occur][#set[occur] + 1] = rank
    end
  end

  for i = 4, 1, -1 do
    if set[i] then
      table.sort( set[i], function( a, b ) return a > b end )
      for k = 1,#set[i] do
        SortedHand[#SortedHand + 1] = set[i][k]
      end
    end
  end

  return SortedHand
end

function HAND:GetHandCode()
  return self.Code
end

function HAND:GetStrength()
  return self.Strength
end

function HAND:GetName()
  return tostring(self)
end
