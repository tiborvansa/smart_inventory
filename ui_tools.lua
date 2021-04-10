local cache = smart_inventory.cache
local crecipes = smart_inventory.crecipes
local txt = smart_inventory.txt
local doc_addon = smart_inventory.doc_addon

local ui_tools = {}
-----------------------------------------------------
-- Group item list and prepare for output
-----------------------------------------------------
-- Parameters:
-- grouped: grouped items list (result of cache.get_list_grouped)
-- groups_sel: smartfs Element (table) that should contain the groups
-- groups_tab: shadow table that with items per group that will be updated in this method
-- Return: updated groups_tab


function ui_tools.update_group_selection(grouped, groups_sel, groups_tab)
	-- save old selection
	local sel_id = groups_sel:getSelected()
	local sel_grp
	if sel_id and groups_tab then
		sel_grp = groups_tab[sel_id]
	end

	-- sort the groups
	local group_sorted = {}
	for _, group in pairs(grouped) do
		table.insert(group_sorted, group)
	end

	table.sort(group_sorted, function(a,b)
		local sort_fixed_order = {
			["all"] = 5,    -- at the begin
			["other"] = 80, -- at the end
			["shape"] = 90, --at the end
		}
		local aval = sort_fixed_order[a.name] or 10
		local bval = sort_fixed_order[b.name] or 10
		if aval ~= bval then
			return aval < bval
		else
			return a.name < b.name
		end
	end)

	-- apply groups to the groups_sel table and to the new groups_tab
	groups_sel:clearItems()
	groups_tab = {}
	for _, group in ipairs(group_sorted) do
		if #group.items > 0 then
			local idx = groups_sel:addItem(group.group_desc.." ("..#group.items..")")
			groups_tab[idx] = group.name
			if sel_grp == group.name then
				sel_id = idx
			end
		end
	end

	-- restore selection
	if not groups_tab[sel_id] then
		sel_id = 1
	end
	groups_sel:setSelected(sel_id)

	return groups_tab
end


-----------------------------------------------------
-- Create trash inventory
-----------------------------------------------------
function ui_tools.create_trash_inv(state, name)
	local player = minetest.get_player_by_name(name)
	local invname = name.."_trash_inv"
	local listname = "trash"
	local inv = minetest.get_inventory({type="detached", name=invname})
	if not inv then
		inv = minetest.create_detached_inventory(invname, {
			allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
				return 0
			end,
			allow_put = function(inv, listname, index, stack, player)
				return 99
			end,
			allow_take = function(inv, listname, index, stack, player)
				return 99
			end,
			on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			end,
			on_put = function(inv, listname, index, stack, player)
				minetest.after(1, function(stack)
					inv:set_stack(listname, index, nil)
				end)
			end,
			on_take = function(inv, listname, index, stack, player)
				inv:set_stack(listname, index, nil)
			end,
		}, name)
	end
	inv:set_size(listname, 1)
end


-----------------------------------------------------
-- Filter a list by search string
-----------------------------------------------------
function ui_tools.filter_by_searchstring(list, search_string, lang_code)
	local filtered_list = {}
	search_string = search_string:lower()
	for _, entry in ipairs(list) do
		local def = minetest.registered_items[entry.item]
		local description = def.description
		if lang_code then
			description = minetest.get_translated_string(lang_code, description)
		end
		if string.find(description:lower(), search_string) or
				string.find(def.name:lower(), search_string) then
			table.insert(filtered_list, entry)
		else
			for _, cgroup in pairs(entry.citem.cgroups) do
				if cgroup.keyword then
					if string.find(cgroup.keyword:lower():gsub("_", ":"), search_string:gsub("_", ":"))then
						table.insert(filtered_list, entry)
						break
					end
				end
				if cgroup.group_desc then
					local group_desc =txt[cgroup.group_desc] or cgroup.group_desc
					if string.find(group_desc:lower(), search_string)then
						table.insert(filtered_list, entry)
						break
					end
				end
			end
		end
	end
	return filtered_list
end

-----------------------------------------------------
-- Get all revealed items available
-----------------------------------------------------
function ui_tools.filter_by_revealed(list, playername, by_item_only)
	if not smart_inventory.doc_items_mod then
		return list
	end
	local revealed_items_cache = {}
	local filtered_list = {}
	for _, entry in ipairs(list) do
		-- check recipes
		local revealed_by_recipe = false
		if by_item_only ~= true and
				cache.citems[entry.item] and
				cache.citems[entry.item].in_output_recipe then
			for _, recipe in ipairs(cache.citems[entry.item].in_output_recipe) do
				if crecipes.crecipes[recipe]:is_revealed(playername, revealed_items_cache) then
					revealed_by_recipe = true
					break
				end
			end
		end
		if revealed_by_recipe or doc_addon.is_revealed_item(entry.item, playername) then
			table.insert(filtered_list, entry)
		end
	end
	return filtered_list
end

-----------------------------------------------------
-- Get all revealed items available
-----------------------------------------------------
function ui_tools.filter_by_top_reveal(list, playername)
	-- check the list for not revealed only. Create search index
	local craftable_only = {}
	for _, entry in ipairs(list) do
		-- only not revealed could be in tipp
		if not doc_addon.is_revealed_item(entry.item, playername) then
			craftable_only[entry.item] = entry
		end
	end

	local rating_tab = {}
	local revealed_items_cache = {}

	for itemname, entry in pairs(craftable_only) do
	-- Check all recipes
		--print("check", itemname)
		local rating_value = 0
		-- Check all items
		for _, recipe in ipairs(cache.citems[itemname].in_craft_recipe) do
			if crecipes.crecipes[recipe] then
				local crecipe = crecipes.crecipes[recipe]
				if not doc_addon.is_revealed_item(crecipe.out_item.name, playername) then
					--print("check recipe out:", crecipe.out_item.name)

					local revealed_by_other_recipe = false
					for _, recipe in ipairs(cache.citems[crecipe.out_item.name].in_output_recipe) do
						if crecipes.crecipes[recipe]:is_revealed(playername, revealed_items_cache) then
							revealed_by_other_recipe = true
							break
						end
					end

					if not revealed_by_other_recipe then
						for recipe_itemname, iteminfo in pairs(crecipe._items) do
							-- in recipe
							if recipe_itemname == itemname or minetest.registered_aliases[recipe_itemname] == itemname then
								rating_value = rating_value + 1
								--print("by name", recipe_itemname, iteminfo.items[recipe_itemname].name)
							elseif recipe_itemname:sub(1, 6) == "group:" and iteminfo.items[itemname] then
								local is_revealed = false
								for alt_itemname, _ in pairs (iteminfo.items) do
									if doc_addon.is_revealed_item(alt_itemname, playername) then
										is_revealed = true
										break
									end
								end
								if not is_revealed then
									--print("by group", recipe_itemname, itemname)
									rating_value = rating_value + 1
								end
							end
						end
					end
				end
			end
			--print("rating", itemname, rating_value)
			rating_tab[itemname] = (rating_tab[itemname] or 0) + rating_value
		end
	end

	-- prepare output list
	local sorted_rating = {}
	for itemname, rating in pairs(rating_tab) do
			table.insert(sorted_rating, {itemname = itemname, rating = rating})
	end
	table.sort(sorted_rating, function(a,b) return a.rating > b.rating end)

	local out_count = 0
	local filtered_list = {}
	local top_rating = 0
	for _, v in ipairs(sorted_rating) do
		-- top 10 but show all with the same rating
		if out_count < 20 or v.rating == top_rating then
			top_rating = v.rating
			local entry = craftable_only[v.itemname]
			if v.rating > 0 then
				entry  = {}
				for kk, vv in pairs(craftable_only[v.itemname]) do
					entry[kk] = vv
				end
				entry.text = v.rating
			end
			table.insert(filtered_list, entry)
			out_count = out_count + 1
		else
			break
		end
	end
	return filtered_list
end

-----------------------------------------------------
-- Select tight groups only to display info about item
-----------------------------------------------------
function ui_tools.get_tight_groups(cgroups)
	local out_list = {}
	for group1, groupdef1 in pairs(cgroups) do
		if groupdef1.keyword then
			out_list[group1] = groupdef1
			for group2, groupdef2 in pairs(out_list) do
				if string.len(group1) > string.len(group2) and
						string.sub(group1,1,string.len(group2)) == group2 then
						-- group2 is top-group of group1. Remove the group2
					out_list[group2] = nil
				elseif string.len(group1) < string.len(group2) and
						string.sub(group2,1,string.len(group1)) == group1 then
						-- group2 is top-group of group1. Remove the group2
					out_list[group1] = nil
				end
			end
		end
	end
	local out_list_sorted = {}
	for group, groupdef in pairs(out_list) do
		table.insert(out_list_sorted, groupdef)
	end
	table.sort(out_list_sorted, function(a,b)
		return a.group_desc < b.group_desc
	end)
	return out_list_sorted
end

-----------------------------------------------------
-- Sort items to groups and decide which groups should be displayed
-----------------------------------------------------
function ui_tools.get_list_grouped(itemtable)
	local grouped = {}
	-- sort the entries to groups
	for _, entry in ipairs(itemtable) do
		if cache.citems[entry.item] then
			for _, group in pairs(cache.citems[entry.item].cgroups) do
				if not grouped[group.name] then
					local group_info = {}
					group_info.name = group.name
					group_info.cgroup = cache.cgroups[group.name]
					group_info.items = {}
					grouped[group.name] = group_info
				end
				table.insert(grouped[group.name].items, entry)
			end
		end
	end

	-- magic to calculate relevant groups
	local itemcount = #itemtable
	local best_group_count = 14
	local best_group_size = (itemcount / best_group_count) * 1.5
	best_group_count = math.floor(best_group_count)
	local sorttab = {}

  local basic_groups = {["tool"] = 98,["food"] = 99,["homedecor"] = 99,["weapons_armor"] = 99,["farming"] = 99
                        ,["castle"] = 99,["mesecon"] = 99,["mod:petz"] = 99,["mod:unifieddyes"] = 99,["shape"]=50
                        ,["clothing"] = 99,["materials"] = 99,["drawers"] = 99,["signs"] = 99, ["norecipe"] = 99}
  local unwanted_groups = {["type:node"] = -1,
                           ["flammable"] = -1,                     
                           ["dig_immediate"] = -1,
                           ["attached_node"] = -1,
                           ["attached_node"] = -1,
                           ["cracky"]=-1,
                           ["crumbly"]=-1,
                           ["choppy"]=-1,
                           ["snappy"]=-1,
                           ["type:craft"]=-1,
                           ["translucent"]=-1,
                           ["oddly_breakable_by_hand"]=-1,
                            }

	for k,v in pairs(grouped) do
    local ismodg = string.find(v.name,"mod:")    

		if #v.items >= itemcount - 10 then
			grouped[k] = nil
		else		  
		
		  if basic_groups[v.name] then v.group_priority = basic_groups[v.name] --minetest.log("info","tool")
		  elseif ismodg then v.group_priority = 2
      elseif unwanted_groups[v.name] then v.group_priority = unwanted_groups[v.name]
      elseif v.parent and v.parent.name and unwanted_groups[v.parent.name] then v.group_priority = unwanted_groups[v.parent.name]
		  else v.group_priority = 0 end		   
			v.group_size = #v.items
			v.unique_count = #v.items
			v.best_group_size = best_group_size
			v.diff = math.abs(v.group_size - v.best_group_size)
			table.insert(sorttab, v)
		end
	end

	local outtab = {}
	local assigned_items = {}
	
	--local smart_inventory_all_groups = minetest.setting_getbool("smart_inventory_all_groups")
	
	
	if best_group_count > 0 then
		for i = 1, best_group_count do
			-- sort by best size
			table.sort(sorttab, function(a,b)
				if a.group_priority ==  b.group_priority then return a.diff < b.diff				
				else return a.group_priority > b.group_priority end
			end)

			local sel = sorttab[1]

			if not sel then
				break
			end
			outtab[sel.name] = {
				name = sel.name,
				group_desc = sel.cgroup.group_desc,
				items = sel.items
			}
			table.remove(sorttab, 1)


			for _, item in ipairs(sel.items) do
				assigned_items[item.item] = true
			 --update the not selected groups
			 	for _, group in pairs(cache.citems[item.item].cgroups) do
					if group.name ~= sel.name then
						local u = grouped[group.name]
						if u and u.unique_count and u.group_size > 0 then
							u.unique_count = u.unique_count-1
							if (u.group_size < u.best_group_size) or
									(u.group_size - u.best_group_size) < (u.best_group_size - u.unique_count) then
								sel.diff = u.best_group_size - u.unique_count
							end
						end
					end
				end 
			end

			for idx = #sorttab, 1, -1 do
				if sorttab[idx].unique_count < 3 or
					( sel.cgroup.parent and sel.cgroup.parent.name == sorttab[idx].name ) or
					( sel.cgroup.childs and sel.cgroup.childs[sorttab[idx].name] )
				then
					grouped[sorttab[idx].name] = nil
					table.remove(sorttab, idx)
				end
			end
		end
	end

	-- fill other group
	local other = {}
	for _, item in ipairs(itemtable) do
		if not assigned_items[item.item] then
			table.insert(other, item)
		end
	end
	

	-- default groups
	outtab.all = {}
	outtab.all.name = "all"
	outtab.all.items = itemtable

	outtab.other = {}
	outtab.other.name = "other"
	outtab.other.items = other

	if txt then
		outtab.all.group_desc = txt[outtab.all.name] or "all"
		outtab.other.group_desc = txt[outtab.other.name] or "other"
	else
		outtab.all.group_desc = "all"
		outtab.other.group_desc = "other"
	end

	return outtab
end


local function unifieddyes_sort_order() end
if minetest.global_exists("unifieddyes") then
	function unifieddyes_sort_order(entry)
		local ret = unifieddyes.getpaletteidx(entry.item, "extended")
		if ret then
			local ret2 = string.format("%02X", ret)
			return 'dye '..ret2
		end
	end
end

local function armor_sort_order(entry) end
if minetest.global_exists("armor") then
	function armor_sort_order(entry)
		if not entry.citem.cgroups["armor"] then
			return
		end
		local split = entry.item:split("_")
		return "armor "..split[#split] .. entry.item
	end
end

-----------------------------------------------------
-- Prepare root lists for all users
-----------------------------------------------------
local function prepare_root_lists()
	ui_tools.root_list = {}
	ui_tools.root_list_shape = {}
	ui_tools.root_list_all = {}

	for itemname, citem in pairs(cache.citems) do
		local entry = {
			citem = citem,
			itemdef = minetest.registered_items[itemname],

			-- buttons_grid related
			item = itemname,
			is_button = true
		}

		entry.sort_value = unifieddyes_sort_order(entry) or armor_sort_order(entry) or itemname
		citem.ui_item = entry
		local isshape = string.find(itemname,":stair_") or string.find(itemname,":slope_")  or 
		                string.find(itemname,":micro_") or string.find(itemname,":slab_")  or
		                string.find(itemname,":wall_") or string.find(itemname,":panel_") or 
		                string.find(itemname,":arrowslit_") or string.find(itemname,":pillar_") or
		                string.find(itemname,"technic:") or string.find(itemname,"pipeworks:") or
		                string.find(itemname,"computer:") or string.find(itemname,"heads:") or
		                string.find(itemname,"plasmascreen:") or string.find(itemname,"wine:")
		if not isshape then 
		if citem.cgroups["shape"] then
			table.insert(ui_tools.root_list_shape, entry)
		else
			table.insert(ui_tools.root_list, entry)
			table.insert(ui_tools.root_list_all, entry)
		end
		end 
		--table.insert(ui_tools.root_list_all, entry)
	end
end
cache.register_on_cache_filled(prepare_root_lists)

-----------------------------------------------------
-- Take a visual feedback on pressing button since the minetest client does nothing visible on pressing button
-----------------------------------------------------
function ui_tools.image_button_feedback(playername, page, element)
	local function reset_background(playername, page, element)
		local state = smart_inventory.get_page_state(page, playername)
		if state then
			state:get(element):setBackground(nil)
			state.location.rootState:show()
		end
	end

	local state = smart_inventory.get_page_state(page, playername)
	if state then
		state:get(element):setBackground("halo.png")
		minetest.after(0.3, reset_background, playername, page, element)
	end

end
--------------------------------
return ui_tools
