if CLIENT then
  --Disabling mipmaps in VTFEdit didn't do anything for gmod
  matproxy.Add( {
    name = "PokerStack",

    init = function( self, mat, values )
      self.ResultTo = values.resultvar
    end,

    bind = function( self, mat, ent )
      if not IsValid(ent) then return end
      local weight = ent:GetFlexWeight(0)
      local max, min = ent:GetRenderBounds()
      if max != max + Vector( 0, 0, 30) and not ent.HasRenderAdjust then
        ent:SetRenderBounds(min, max + Vector(0,0, 30) )
        ent.HasRenderAdjust = true
      end
      if weight == 0 then return end
      mat:SetVector( self.ResultTo, Vector(1, 1 + (1.5 * weight)) )
    end
  } )
end
