local txt = smart_inventory.txt

--------------------------------------------------------------
-- Filter class
--------------------------------------------------------------
local filter_class = {}
local filter_class_mt = {__index = filter_class}

function filter_class:check_item_by_name(itemname)
	if minetest.registered_items[itemname] then
		return self:check_item_by_def(minetest.registered_items[itemname])
	end
end

function filter_class:check_item_by_def(def)
	error("check_item_by_def needs redefinition:"..debug.traceback())
end

function filter_class:_get_description(group)
	if txt then
		if txt[group.name] then
			return txt[group.name].." ("..group.name..")"
		elseif group.parent and group.parent.childs[group.name] and txt[group.parent.name] then
			return txt[group.parent.name].." "..group.parent.childs[group.name].." ("..group.name..")"
		else
			return group.name
		end
	else
		return group.name
	end
end
filter_class.get_description = filter_class._get_description

function filter_class:_get_keyword(group)
	return group.group_desc
end

filter_class.get_keyword = filter_class._get_keyword

function filter_class:is_valid(group)
	return true
end

local filter = {}
filter.registered_filter = {}

function filter.get(name)
	return filter.registered_filter[name]
end

function filter.register_filter(def)
	assert(def.name, "filter needs a name")
	assert(def.check_item_by_def, "filter function check_item_by_def required")
	assert(not filter.registered_filter[def.name], "filter already exists")
	setmetatable(def, filter_class_mt)
	filter.registered_filter[def.name] = def
end


-- rename groups for beter consistency
filter.group_rename = {
	customnode_default = "customnode",
}

-- group configurations per basename
--   true means is dimension
--   1 means replace the base only ("food_choco_powder" => food:choco_powder")
filter.base_group_config = {
	armor = true,
	physics = true,
	basecolor = true,
	excolor = true,
	color = true,
	unicolor = true,
	food = 1,
	customnode = true,
}

-- hide this groups
filter.group_hide_config = {
	armor_count = true,
	not_in_creative_inventory = false,
}

-- value of this group will be recalculated to %
filter.group_wear_config = {
	armor_use = true,
}

-- Ususally 1 means true for group values. This is an exceptions table for this rule
filter.group_with_value_1_config = {
	oddly_breakable_by_hand = true,
}

--------------------------------------------------------------
-- Filter group
--------------------------------------------------------------
filter.register_filter({
		name = "group",
		check_item_by_def = function(self, def)
			local ret = {}
			for k_orig, v in pairs(def.groups) do
				local k = filter.group_rename[k_orig] or k_orig
				local mk, mv

				-- Check group base
				local basename
				for z in k:gmatch("[^_]+") do
					basename = z
					break
				end
				local basegroup_config = filter.base_group_config[basename]
				if basegroup_config == true then
					mk = string.gsub(k, "_", ":")
				elseif basegroup_config == 1 then
					mk = string.gsub(k, "^"..basename.."_", basename..":")
				else
					mk = k
				end

				-- stack wear related value
				if filter.group_wear_config[k] then
					mv = tostring(math.floor(v / 65535 * 10000 + 0.5)/100).." %"
				-- value-expandable groups
				elseif v ~= 1 or k == filter.group_with_value_1_config[k] then
					mv = v
				else
					mv = true
				end

				if v ~= 0 and mk and not filter.group_hide_config[k] then
					ret[mk] = mv
				end
			end
			return ret
		end,
	})

filter.register_filter({
		name = "type",
		check_item_by_def = function(self, def)
			return self.name..":"..def.type
		end,
		get_keyword = function(self, group)
			if group.name ~= self.name then
				return group.parent.childs[group.name]
			end
		end
	})

filter.register_filter({
		name = "mod",
		check_item_by_def = function(self, def)
			if def.mod_origin then
				return self.name..":"..def.mod_origin
			end
		end,
		get_keyword = function(self, group)
			if group.name ~= self.name then
				return group.parent.childs[group.name]
			end
		end
	})

filter.register_filter({
		name = "translucent",
		check_item_by_def = function(self, def)
			if def.sunlight_propagates ~= 0 then
				return def.sunlight_propagates
			end
		end,
	})

filter.register_filter({
		name = "light",
		check_item_by_def = function(self, def)
			if def.light_source ~= 0 then
				return def.light_source
			end
		end,
	})

filter.register_filter({
		name = "metainv",
		check_item_by_def = function(self, def)
			if def.allow_metadata_inventory_move or
					def.allow_metadata_inventory_take or
					def.allow_metadata_inventory_put or
					def.on_metadata_inventory_move or
					def.on_metadata_inventory_take or
					def.on_metadata_inventory_put then
				return true
			end
		end,
	})



local shaped_groups = {}
local shaped_list = minetest.setting_get("smart_inventory_shaped_groups") or "carpet,door,fence,stair,slab,wall,micro,panel,slope"
if shaped_list then
	for z in shaped_list:gmatch("[^,]+") do
		shaped_groups[z] = true
	end
end



filter.register_filter({
		name = "shape",
		check_item_by_def = function(self, def)
			local door_groups
			if shaped_groups["door"] then
				local door_filter = filter.get("door")
				door_groups = door_filter:check_item_by_def(def)
				if door_groups and door_groups.door then
					return true
				end
			end

			for k, v in pairs(def.groups) do
				if k ~= "door" and shaped_groups[k] then
					return true
				end
			end
		end,
	})

filter.register_filter({
		name = "food",
		check_item_by_def = function(self, def)
      for k, v in pairs(def.groups) do
				if  string.find(k,"food_") then
					return true
				end
			end	
			if string.find(def.name,"food_") or string.find(def.name,"food:") or string.find(def.name,"_food") 
			   or string.find(def.name,"mtfood") or string.find(def.name,"pie:")
			     then return true 
        end	
      if def.recipetype == "cooking" then return true  
			 end
		end,
	})

filter.register_filter({
		name = "homedecor",
		check_item_by_def = function(self, def)
			if string.find(def.name,"homedecor") or string.find(def.name,"curtain") 
			   or string.find(def.name,"furniture") or string.find(def.name,"Irfurn")
			     then return true
        end	
		end,
	})

filter.register_filter({
		name = "farming",
		check_item_by_def = function(self, def)
      for k, v in pairs(def.groups) do
				if  string.find(k,"farming") then
					return true
				end
			end
			if string.find(def.name,"farming") or string.find(def.name,"crops") or string.find(def.name,"bonemeal") 
			   or string.find(def.name,"cottages") or string.find(def.name,"compost")
          then return true 
        end
		end,
	})

filter.register_filter({
    name = "weapons_armor",
    check_item_by_def = function(self, def)
      if def.tool_capabilities and def.tool_capabilities.damage_groups then
        for k, v in pairs(def.tool_capabilities.damage_groups) do
          if v ~= 0 and (def.tool_capabilities.damage_groups["fleshy"] or 1) > 4
                and not (string.find(def.name,"default:axe") or string.find(def.name,"default:pick_")
                    or string.find(def.name,"shovel")  or string.find(def.name,"sickles") 
                    or def.name == "anvil:hammer")
                then
            return true
          end
        end
      end
      if def.armor_groups then
        return true
      end
      if string.find(def.name,"weapon") or string.find(def.name,"cannon")
        or string.find(def.name,"spykes") or  string.find(def.name,"armor")
        or string.find(def.name,"armour") or  string.find(def.name,"sword")
      then return true
      end  
    end
  })

filter.register_filter({
    name = "castle",
    check_item_by_def = function(self, def)
      local mname = def.name:split(":")[1]
      local pname = def.name:split(":")[2]
      if string.find(def.name,"castle") or string.find(def.name,"princess") 
          --or string.find(def.name,"ropes:")
           then return true
        end
      if mname == "jonez" then return true end   
    end,
  })

filter.register_filter({
    name = "mesecon",
    check_item_by_def = function(self, def)
      if string.find(def.name,"mesecon") --or string.find(def.name,"curtain") 
           then return true
        end 
    end,
  })

local tools_machines = {["anvil:anvil"]=1,["crafting_bench:workbench"]=1,["default:furnace"]=1,["moreblocks:circular_saw"]=1
      ,["doc_encyclopedia:encyclopedia"]=1,["doc_identifier:identifier_solid"]=1,["default_torch"]=1,}

filter.register_filter({
		name = "tool",
		check_item_by_def = function(self, def)
      local mname = def.name:split(":")[1]
      local pname = def.name:split(":")[2]		
      if mname == "cartographer" or mname == "binoculars" or mname == "beds"  or mname == "campfire"
         or string.find(def.name,"book") or mname == "sailing_kit"   
         then return true end		
      if tools_machines[def.name] then return true end
      --only tools   
		  if def.type ~= "tool" then return end 
			local rettab = {}  
			--without weapons  
			local weapon_filter = filter.get("weapons_armor")
      local weapon_groups = weapon_filter:check_item_by_def(def)
      if weapon_groups ~= nil and not (string.find(def.name,"default:axe"))  then return
        end
        
      if def.tool_capabilities then  
			 for k, v in pairs(def.tool_capabilities) do
				  if type(v) ~= "table" and v ~= 0 then
				     rettab["tool:"..k] = v
				  end
			 end
			else return true 
			end 
			return rettab
		end,
		get_keyword = function(self, group)
			if group.name == "tool" then
				return nil
			else
				return self:_get_keyword(group)
			end
		end
	})



filter.register_filter({
		name = 'clothing',
		check_item_by_def = function(self, def)
			if string.find(def.name,"clothing") or string.find(def.name,"wool")
        --or string.find(def.name,"spykes")  
        then return true
      end
		end
	})

filter.register_filter({
    name = 'materials',
    check_item_by_def = function(self, def)
      local mname = def.name:split(":")[1]
      local pname = def.name:split(":")[2]
      if mname == "abriglass" or string.find(def.name,"materials")
        or mname == "unifiedbricks" or mname == "xpanes"  
        or mname == "building_blocks" or mname == "mtg_plus" 
        or mname == "stained_glass" or mname == "cement" 
        or (mname == "moreblocks" and def.type == "node")
        or (mname == "moreores" and def.type == "node")
        or (mname == "ethereal" and def.type == "node")
        then return true
      end
      if mname == "default" and def.type == "node" and not (def.groups["attached_node"] or def.groups["sapling"])
        then return true
        end 
    end
  })

filter.register_filter({
    name = 'drawers',
    check_item_by_def = function(self, def)
      local mname = def.name:split(":")[1]
      local pname = def.name:split(":")[2]    
      if string.find(def.name,"drawer") or string.find(def.name,"hopper")
        or mname == "ropes" or mname == "cart" or mname == "boost_cart"  
        then return true 
      end
    end
  })

filter.register_filter({
    name = 'signs',
    check_item_by_def = function(self, def)
    local mname = def.name:split(":")[1]
    local pname = def.name:split(":")[2]
      if mname == "ehlphabet" or mname == "cube_nodes" or mname == "hiking"  
        then return true
      end
    end
  })

-- Burn times
filter.register_filter({
		name = "fuel",
		check_item_by_def = function(self, def)
			local burntime = minetest.get_craft_result({method="fuel",width=1,items={def.name}}).time
			if burntime > 0 then
				return "fuel:"..burntime
			end
		end
})

filter.register_filter({
    name = "norecipe",
    check_item_by_def = function(self, def)
      if minetest.get_craft_recipe(def.name).items == nil then return true end
    end
})

-- Group assignment done in cache framework internally
filter.register_filter({
		name = "recipetype",
		check_item_by_def = function(self, def) end,
		get_keyword = function(self, group)
			if group.name ~= self.name then
				return group.parent.childs[group.name]
			end
		end
})

-- Group assignment done in cache framework internally
filter.register_filter({
		name = "ingredient",
		check_item_by_def = function(self, def) end,
		get_description = function(self, group)
			local itemname = group.name:sub(12)
			if txt and txt["ingredient"] and
					minetest.registered_items[itemname] and minetest.registered_items[itemname].description then
				return txt["ingredient"] .." "..minetest.registered_items[itemname].description.." ("..group.name..")"
			else
				return group.name
			end
		end,
		get_keyword = function(self, group)
			-- not searchable by ingedient
			return nil
		end,
		is_valid = function(self, groupname)
			local itemname = groupname:sub(12)
			if itemname ~= "" and minetest.registered_items[itemname] then
				return true
			end
		end
	})


local door_groups
local function fill_door_groups()
	door_groups = {}
	for _, extend_def in pairs(minetest.registered_items) do
		local base_def
		if extend_def.groups and extend_def.groups.door then
			if extend_def.door then
				base_def = minetest.registered_items[extend_def.door.name]
			elseif extend_def.drop and type(extend_def.drop) == "string" then
				base_def = minetest.registered_items[extend_def.drop]
			end
		end
		if base_def then
			door_groups[base_def.name] = extend_def
			door_groups[extend_def.name] = false
		end
	end
end

filter.register_filter({
		name = "door",
		check_item_by_def = function(self, def)
			if not door_groups then
				fill_door_groups()
			end
			if not door_groups[def.name] then
				return
			end

			local group_filter = filter.get("group")
			local ret = group_filter:check_item_by_def(door_groups[def.name])
			if ret then
				ret["not_in_creative_inventory"] = nil
				return ret
			end
		end
	})

--[[ disabled since debug.getupvalue is not usable to secure environment
filter.register_filter({
    name = "food",
    check_item_by_def = function(self, def)
      if def.on_use then
        local name,change=debug.getupvalue(def.on_use, 1)
        if name~=nil and name=="hp_change" and change > 0 then
          return tostring(change)
        end
      end
    end,
  })

filter.register_filter({
    name = "toxic",
    check_item_by_def = function(self, def)
      if def.on_use then
        local name,change=debug.getupvalue(def.on_use, 1)
        if name~=nil and name=="hp_change" and change < 0 then
          return tostring(change)
        end
      end
    end,
  })
]]

--[[ does it sense to filter them? I cannot define the human readable groups for them
filter.register_filter({
    name = "drawtype",
    check_item_by_def = function(self, def)
      if def.drawtype ~= "normal" then
        return def.drawtype
      end
    end,
  })

]]


----------------
return filter

