Deck = {}

local DECK  = {
	__tonumber = function(self)
		return #self
	end
}

DECK.__index = DECK
DECK.__concat = DECK.__tostring

local suits = { "H", "D", "S", "C" }

debug.getregistry().Deck = DECK

function Deck.Create()
	local deck = {}
	for i = 1, 13 do
		for k,v in pairs(suits) do
			card = {}
			card.suit = v
			card.rank = i
			deck[#deck + 1] = card
		end
	end
	local ret = setmetatable(deck, DECK)
	ret:Shuffle()
	return ret
end

function DECK:Shuffle()
	for i = #self, 2, -1 do
		local j = math.random(i)
		self[i], self[j] = self[j], self[i]
	end
end

function DECK:PopCards(amt)
	local Result = {}
	for i = #self, #self - (amt - 1), -1 do
		Result[#Result + 1] = self[i]
		self[i] = nil
	end
	return Result
end
