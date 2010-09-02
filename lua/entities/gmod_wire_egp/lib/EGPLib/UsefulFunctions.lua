--------------------------------------------------------
-- e2function Helper functions
--------------------------------------------------------
local EGP = EGP

----------------------------
-- IsDifferent check
----------------------------
function EGP:IsDifferent( tbl1, tbl2 )
	for k,v in ipairs( tbl1 ) do
		if (!tbl2[k] or tbl2[k].ID != v.ID) then -- Different ID?
			return true
		else
			for k2,v2 in pairs( v ) do
				if (k2 != "BaseClass") then
					if (tbl2[k][k2] or tbl2[k][k2] != v2) then -- Is any setting different?
						return true
					end
				end
			end
		end
	end
	
	for k,v in ipairs( tbl2 ) do -- Were any objects removed?
		if (!tbl1[k]) then
			return true
		end
	end
	
	return false
end
			

----------------------------
-- IsAllowed check
----------------------------
function EGP:IsAllowed( E2, Ent )
	if (!EGP:ValidEGP( Ent )) then return false end
	if (E2 and E2.entity and E2.entity:IsValid()) then
		if (!E2Lib.isOwner(E2,Ent)) then
			return E2Lib.isFriend(E2.player,E2Lib.getOwner(Ent))
		else
			return true
		end
	end
	return false
end

----------------------------
-- Object existance check
----------------------------
function EGP:HasObject( Ent, index )
	if (!EGP:ValidEGP( Ent )) then return false end
	index = math.Round(math.Clamp(index or 1, 1, self.ConVars.MaxObjects:GetInt()))
	if (!Ent.RenderTable or #Ent.RenderTable == 0) then return false end
	for k,v in ipairs( Ent.RenderTable ) do
		if (v.index == index) then
			return true, k, v
		end
	end
	return false
end

----------------------------
-- Object order changing
----------------------------
function EGP:SetOrder( Ent, from, to )
	if (!Ent.RenderTable or #Ent.RenderTable == 0) then return false end
	if (Ent.RenderTable[from]) then
		to = math.Clamp(math.Round(to or 1),1,#Ent.RenderTable)
		local temp = Ent.RenderTable[from]
		table.remove( Ent.RenderTable, from )
		table.insert( Ent.RenderTable, to, temp )
		if (SERVER) then Ent.RenderTable[to].ChangeOrder = {from,to} end
		return true
	end
	return false
end
----------------------------
-- Create / edit objects
----------------------------

function EGP:CreateObject( Ent, ObjID, Settings )
	if (!self:ValidEGP( Ent )) then return false end

	Settings.index = math.Round(math.Clamp(Settings.index or 1, 1, self.ConVars.MaxObjects:GetInt()))
	
	local bool, k, v = self:HasObject( Ent, Settings.index )
	if (bool) then -- Already exists. Change settings:
		if (v.ID != ObjID) then -- Not the same kind of object, create new
			local Obj = {}
			Obj = self:GetObjectByID( ObjID )
			self:EditObject( Obj, Settings )
			Obj.index = Settings.index
			Ent.RenderTable[k] = Obj
			return true, Obj
		else
			return self:EditObject( v, Settings ), v
		end
	else -- Did not exist. Create:
		local Obj = self:GetObjectByID( ObjID )
		self:EditObject( Obj, Settings )
		Obj.index = Settings.index
		table.insert( Ent.RenderTable, Obj )
		return true, Obj
	end
end

function EGP:EditObject( Obj, Settings )
	local ret = false
	for k,v in pairs( Settings ) do
		if (Obj[k] and Obj[k] != v) then
			Obj[k] = v
			ret = true
		end
	end
	return ret
end

--------------------------------------------------------
-- Transmitting / Receiving helper functions
--------------------------------------------------------
-----------------------
-- Material
-----------------------
EGP.SavedMaterials = {}
function EGP:GetSavedMaterial( Mat )
	if (!table.HasValue( self.SavedMaterials, Mat )) then
		self:SaveMaterial( Mat )
		return "?" .. Mat
	else
		local str
		for k,v in ipairs( self.SavedMaterials ) do
			if (v == Mat) then
				str = k
				break
			end
		end
		return "." .. str
	end
end

function EGP:SaveMaterial( Mat )
	if (!Mat or #Mat == 0) then return end
	if (!table.HasValue( self.SavedMaterials, Mat )) then
		table.insert( self.SavedMaterials, Mat )
	end
end

function EGP:SendMaterial( obj ) -- ALWAYS use this when sending material
	local str
	
	-- "!" = entity
	-- "?" = string
	-- "." = number
	
	if (type(obj.material) == "Entity") then
		if (!obj.material:IsValid()) then 
			str = ""
		else
			str = "!" .. obj.material:EntIndex()
		end
	elseif (type(obj.material) == "string") then
		if (obj.material == "") then
			str = ""
		else
			str = self:GetSavedMaterial( obj.material )
		end
	end
	EGP.umsg.String( str )
end

function EGP:ReceiveMaterial( tbl, um ) -- ALWAYS use this when receiving material
	local mat = um:ReadString()
	local first = mat:Left(1)
	if (first == "!" or first == "?" or first == ".") then
		mat = mat:Right(-2)
		if (first == "!") then
			mat = Entity(tonumber(mat))
		elseif (first == ".") then
			for k,v in pairs( self.SavedMaterials ) do
				if (mat == tostring(k)) then
					mat = v
					break
				end
			end
		elseif (first == "?") then
			self:SaveMaterial( mat )
		end
	end
	tbl.material = mat
end

-----------------------
-- Other
-----------------------
function EGP:SendPosSize( obj )
	EGP.umsg.Short( obj.w )
	EGP.umsg.Short( obj.h )
	EGP.umsg.Short( obj.x )
	EGP.umsg.Short( obj.y )
end

function EGP:SendColor( obj )
	EGP.umsg.Char( obj.r - 128 )
	EGP.umsg.Char( obj.g - 128 )
	EGP.umsg.Char( obj.b - 128 )
	if (obj.a) then EGP.umsg.Char( obj.a - 128 ) end
end

function EGP:ReceivePosSize( tbl, um ) -- Used with SendPosSize
	tbl.w = um:ReadShort()
	tbl.h = um:ReadShort()
	tbl.x = um:ReadShort()
	tbl.y = um:ReadShort()
end

function EGP:ReceiveColor( tbl, obj, um ) -- Used with SendColor
	tbl.r = um:ReadChar() + 128
	tbl.g = um:ReadChar() + 128
	tbl.b = um:ReadChar() + 128
	if (obj.a) then tbl.a = um:ReadChar() + 128 end
end

--------------------------------------------------------
-- Other
--------------------------------------------------------
function EGP:ValidEGP( Ent )
	return (Ent and Ent:IsValid() and (Ent:GetClass() == "gmod_wire_egp" or Ent:GetClass() == "gmod_wire_egp_hud" or Ent:GetClass() == "gmod_wire_egp_emitter"))
end