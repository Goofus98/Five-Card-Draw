do
  local suits = { "H", "D", "S", "C" }
  Poker.Textures = {}
  for rank = 1, 13 do
    for k,suit in pairs(suits) do
      local offset_x = 0.005
      local offset_y = 0.005
      if rank != 13 then
        offset_x = offset_x + (rank * 0.0765)
      end
      if k != 1 then
        offset_y = offset_y + (0.247 * (k-1))
      end
      Poker.Textures[ suit .. "_" .. rank] =  CreateMaterial( "deck_" .. suit .. "_" .. rank, "UnlitGeneric", {
            ["$basetexture"] = "ui/poker/playing_cards_deck",
            ["$basetexturetransform"] = "center .0 .0 scale  0.0725 0.25 rotate 0 translate " .. offset_x .. " " .. offset_y,
            --faster to render?
            ["$alphatest"] = 1,
            ["$alphatestreference"] = .7,
            ["$allowalphatocoverage"] = 1
      } )
    end
  end
end
