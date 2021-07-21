util.PrecacheModel( "models/goofus/poker/poker_deck.mdl" )
util.PrecacheModel( "models/goofus/poker/poker_chip.mdl" )
util.PrecacheModel( "models/phxtended/trieq1x1x1solid.mdl" )
if SERVER then
  AddCSLuaFile()
  include "poker/sh_init.lua"
  include "poker/sv_init.lua"
  include "poker/meta/sh_player.lua"
  include "poker/meta/sv_player.lua"
  include "poker/handeval/sv_init.lua"
  include "poker/deck/sv_init.lua"
  AddCSLuaFile "poker/meta/sh_player.lua"
  AddCSLuaFile "poker/sh_init.lua"
  AddCSLuaFile "poker/ui/cl_mat.lua"
  AddCSLuaFile "poker/cl_init.lua"
  AddCSLuaFile "poker/ui/cl_hud.lua"
  AddCSLuaFile "poker/ui/cl_vgui.lua"
end
if CLIENT then
  include "poker/meta/sh_player.lua"
  include "poker/sh_init.lua"
  include "poker/ui/cl_mat.lua"
  include "poker/cl_init.lua"
  include "poker/ui/cl_hud.lua"
  include "poker/ui/cl_vgui.lua"
end
