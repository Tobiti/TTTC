local plymeta = FindMetaTable("Player")

if not plymeta then return end

plymeta.classWeapons = {}
plymeta.classItems = {}

AccessorFunc(plymeta, "customClass", "CustomClass", FORCE_NUMBER)

function plymeta:GetClassData()
	return GetClassByIndex(self:GetCustomClass())
end

function plymeta:HasCustomClass()
	return self:GetCustomClass() and self:GetCustomClass() ~= CLASSES.UNSET.index
end

if SERVER then
	function plymeta:UpdateCustomClass(index)
		self:SetCustomClass(index)

		net.Start("TTTCSendCustomClass")
		net.WriteUInt(index - 1, CLASS_BITS)
		net.Send(self)

		hook.Run("TTTCUpdatedCustomClass", self)
	end

	function plymeta:SetCustomClassOptions(index1, index2)
		net.Start("TTTCSendCustomClassOptions")
		net.WriteUInt(index1 - 1, CLASS_BITS)
		net.WriteUInt(index2 - 1, CLASS_BITS)
		net.Send(self)

		hook.Run("TTTCUpdatedCustomClassOptions", self)
	end

	function plymeta:GiveClassWeapon(wep)
		local newWep = wep

		if not newWep then return end

		local rt = self:Give(newWep)
		if rt and not table.HasValue(self.classWeapons, newWep) then
			table.insert(self.classWeapons, newWep)
		end

		local wepEntity = self:GetWeapon(newWep)
		if IsValid(wepEntity) then
			wepEntity:SetNWBool("TTTC_class_weapon", true)
			wepEntity.AllowDrop = false
		end

		return rt
	end

	function plymeta:GiveClassEquipmentItem(id)
		local rt = self:GiveEquipmentItem(id)

		if rt and not table.HasValue(self.classItems, id) then
			table.insert(self.classItems, id)
		end

		return rt
	end

	function plymeta:GiveServerClassWeapon(cls, clip1, clip2)
		if not self:HasCustomClass() then return end

		local w = self:GiveClassWeapon(cls)

		if not IsValid(w) then return end

		local newCls = w:GetClass()
		local cd = self:GetClassData()

		if not table.HasValue(cd.weapons, newCls) then
			table.insert(cd.weapons, newCls)

			net.Start("TTTCSyncClassWeapon")
			net.WriteString(newCls)
			net.Send(self)
		end

		if self:HasWeapon(newCls) then
			self:AddBought(cls)

			if w.WasBought then
				-- some weapons give extra ammo after being bought, etc
				w:WasBought(self)
			end

			if clip1 then
				w:SetClip1(clip1)
			end

			if clip2 then
				w:SetClip2(clip2)
			end

			timer.Simple(0.5, function()
				if not IsValid(self) then return end

				net.Start("TTT_BoughtItem")
				net.WriteString(cls)
				net.Send(self)
			end)

			hook.Run("TTTOrderedEquipment", self, cls, nil)
		end
	end

	function plymeta:GiveServerClassItem(id)
		if not id or not self:HasCustomClass() then return end

		self:GiveClassEquipmentItem(id)
		self:AddBought(id)

		local cd = self:GetClassData()

		if not table.HasValue(cd.items, id) then
			table.insert(cd.items, id)

			net.Start("TTTCSyncClassItem")
			net.WriteString(id)
			net.Send(self)
		end

		timer.Simple(0.5, function()
			if not IsValid(self) then return end

			local item = items.GetStored(id)
			if item and isfunction(item.Bought) then
				item:Bought(self)
			end

			net.Start("TTT_BoughtItem")
			net.WriteString(id)
			net.Send(self)
		end)

		hook.Run("TTTOrderedEquipment", self, id, id) -- hook.Run("TTTOrderedEquipment", self, id, true) -- i know, looks stupid but thats the way TTT does
	end

	function plymeta:ResetCustomClass()
		hook.Run("TTTCResetCustomClass", self)

		if self.classWeapons then
			for _, wep in ipairs(self.classWeapons) do
				if self:HasWeapon(wep) then
					self:StripWeapon(wep)
				end
			end
		end

		--[[
		if self.classItems then
			for _, equip in pairs(self.classItems) do
				self.equipment_items = bit.bxor(self.equipment_items, equip)
			end

			self:SendEquipment()
		end
		]]--

		self.classWeapons = {}
		self.classItems = {}

		self:UpdateCustomClass(CLASSES.UNSET.index)
	end

	net.Receive("TTTCClientSendCustomClass", function(len, ply)
		local cls = net.ReadUInt(CLASS_BITS) + 1

		if not ply.SetCustomClass then return end

		ply:ResetCustomClass()
		ply:UpdateCustomClass(cls)

		if ply:IsActive() then
			local cd = ply:GetClassData()
			local weaps = cd.weapons
			local itms = cd.items

			if weaps and #weaps > 0 then
				for _, v in ipairs(weaps) do
					ply:GiveServerClassWeapon(v)
				end
			end

			if itms and #itms > 0 then
				for _, v in ipairs(itms) do
					ply:GiveServerClassItem(v)
				end
			end
		end
	end)

	net.Receive("TTTCClientSendCustomClassChoice", function(len, ply)
		local isRandom = net.ReadBool()
		local cls = nil

		if isRandom then
			if #FREECLASSES == 0 then
				local rand = math.random(1, #POSSIBLECLASSES)

				cls = POSSIBLECLASSES[rand].index
			else
				local rand = math.random(1, #FREECLASSES)

				cls = FREECLASSES[rand].index

				table.remove(FREECLASSES, rand)
			end
		else
			cls = net.ReadUInt(CLASS_BITS) + 1
		end

		if not ply.SetCustomClass then return end

		ply:ResetCustomClass()
		ply:UpdateCustomClass(cls)

		table.RemoveByValue(FREECLASSES, cls)

		if ply:IsActive() then
			local cd = ply:GetClassData()
			local weaps = cd.weapons
			local itms = cd.items

			if weaps and #weaps > 0 then
				for _, v in ipairs(weaps) do
					ply:GiveServerClassWeapon(v)
				end
			end

			if itms and #itms > 0 then
				for _, v in ipairs(itms) do
					ply:GiveServerClassItem(v)
				end
			end
		end
	end)
else
	net.Receive("TTTCSendCustomClass", function(len)
		local client = LocalPlayer()
		local cls = net.ReadUInt(CLASS_BITS) + 1

		if not client.SetCustomClass then return end

		client:SetCustomClass(cls)

		hook.Run("TTTCUpdatedCustomClass", client)
	end)

	net.Receive("TTTCSendCustomClassOptions", function(len)
		local cls1 = net.ReadUInt(CLASS_BITS) + 1
		local cls2 = net.ReadUInt(CLASS_BITS) + 1

		hook.Run("TTTCUpdatedCustomClassOptions", cls1, cls2)
	end)

	net.Receive("TTTCSyncClassWeapon", function(len)
		local client = LocalPlayer()
		local wep = net.ReadString()

		if not client:HasCustomClass() then return end

		local cd = client:GetClassData()

		if not table.HasValue(cd.weapons, wep) then
			table.insert(cd.weapons, wep)
		end
	end)

	net.Receive("TTTCSyncClassItem", function(len)
		local client = LocalPlayer()
		local id = net.ReadString()

		if not client:HasCustomClass() then return end

		local cd = client:GetClassData()

		if not table.HasValue(cd.items, id) then
			table.insert(cd.items, id)
		end
	end)

	function plymeta:ServerUpdateCustomClass(index)
		net.Start("TTTCClientSendCustomClass")
		net.WriteUInt(index - 1, CLASS_BITS)
		net.SendToServer()
	end
end
