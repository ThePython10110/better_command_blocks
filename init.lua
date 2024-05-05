better_command_blocks = {}

local command_blocks = {
    {"impulse", "Command Block"},
    {"repeating", "Repeating Command Block"},
    {"chain", "Chain Command Block"},
}

local anim = {type = "vertical_frames"}

local mesecons_rules = {
    {x = 0, y = 0, z = 1},
    {x = 0, y = 0, z = -1},
    {x = 0, y = 1, z = 0},
    {x = 0, y = -1, z = 0},
    {x = 1, y = 0, z = 0},
    {x = -1, y = 0, z = 0},
}

local already_run = {}

local function get_string_or(meta, key, fallback)
    local result = meta:get_string(key)
    return result == "" and fallback or result
end

local types = {
    {"Impulse", false},
    {"Repeat", false},
    {"Chain", false},
    {"Impulse", true}, -- true = conditional
    {"Repeat", true},
    {"Chain", true},
}


local function on_rightclick(pos, node, player)
    if not minetest.check_player_privs(player, "better_command_blocks") then return end
    local meta = minetest.get_meta(pos)
    local command = meta:get_string("_command")
    local group = minetest.get_item_group(node.name, "command_block")
    local power = meta:get_string("_power") == "false" and "Always Active" or "Needs Power"
    local result = meta:get_string("_result")
    local delay = get_string_or(meta, "_delay", (group == 2 or group == 5) and "1" or "0")
    local formspec = table.concat({ 
        "formspec_version[4]",
        "size[10,6]",
        "label[0.5,0.5;",ItemStack(node.name):get_short_description(),"]",
        "field[6.5,0.5;2,1;delay;Delay (seconds);",delay,"]",
        "field_close_on_enter[delay;false]",
        "button[8.5,0.5;1,1;set_delay;Set]",
        "field[0.5,2;8,1;command;Command;",minetest.formspec_escape(command),"]",
        "field_close_on_enter[command;false]",
        "button[8.5,2;1,1;set_command;Set]",
        "button[0.5,3.5;3,1;type;",types[group][1],"]",
        "button[3.5,3.5;3,1;conditional;",types[group][2] and "Conditional" or "Unconditional","]",
        "button[6.5,3.5;3,1;power;",power,"]",
        "textarea[0.5,5;9,1;;Previous output;",minetest.formspec_escape(result),"]",
    })
    local player_name = player:get_player_name()
    minetest.show_formspec(player_name, "better_command_blocks:"..minetest.pos_to_string(pos), formspec)
end

local command_block_itemstrings = {}

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if not minetest.check_player_privs(player, "better_command_blocks") then return end
    local pos = minetest.string_to_pos(formname:match("^better_command_blocks:(%(%-?[%d%.]+,%-?[%d%.]+,%-?[%d%.]+%))$"))
    if not pos then return end
    local meta = minetest.get_meta(pos)
    local node = minetest.get_node(pos)
    local group = minetest.get_item_group(node.name, "command_block")
    if group < 1 then return end
    local show_formspec
    if fields.key_enter_field == "command" or fields.set_command then
        show_formspec = true
        meta:set_string("_command", fields.command)
    elseif fields.key_enter_field == "delay" or fields.set_delay then
        show_formspec = true
        local delay = tonumber(fields.delay)
        if delay and delay >= 0 then
            meta:set_string("_delay", fields.delay)
        end
    elseif fields.type then
        local new_group = group + 1
        if new_group == 4 or new_group == 7 then new_group = new_group - 3 end
        local new_node = table.copy(node)
        new_node.name = command_block_itemstrings[new_group]
        minetest.swap_node(pos, new_node)
        if new_group == 2 or new_group == 5 then
            minetest.get_node_timer(pos):start(1)
        else
            minetest.get_node_timer(pos):stop()
        end
        if new_group == 2 or new_group == 5 then -- repeating
            if (tonumber(meta:get_string("_delay")) or 1) < 1 then
                meta:set_string("_delay", "1")
            end
        elseif group == 2 or group == 5 then -- previous = repeating
            if (tonumber(meta:get_string("_delay")) or 1) == 1 then
                meta:set_string("_delay", "0")
            end
        end
        show_formspec = true
    elseif fields.conditional then
        local new_group = group + 3
        if new_group > 6 then new_group = new_group - 6 end
        local new_node = table.copy(node)
        new_node.name = command_block_itemstrings[new_group]
        minetest.swap_node(pos, new_node)
        show_formspec = true
    elseif fields.power then
        local result = fields.power == "Needs Power" and "false" or "true"
        meta:set_string("_power", result)
        if result ~= "true" then
            if group ~= 3 and group ~= 6 then
                better_command_blocks.run(pos)
            end
        end
        show_formspec = true
    end
    if show_formspec then
        on_rightclick(pos, minetest.get_node(pos), player)
    end
end)

local function check_for_chain(pos)
    local dir = minetest.facedir_to_dir(minetest.get_node(pos).param2)
    local next = vector.add(dir, pos)
    local next_group = minetest.get_item_group(minetest.get_node(next).name, "command_block")
    if next_group == 0 then return end
    if next_group == 3 or next_group == 6 then -- chain
        local pos_string = minetest.pos_to_string(next)
        if not already_run[pos_string] then
            better_command_blocks.run(next)
        end
    end
end

function better_command_blocks.run(pos)
    local node = minetest.get_node(pos)
    local meta = minetest.get_meta(pos)
    if meta:get_string("_power") ~= "false" then
        if meta:get_string("_mesecons_active") ~= "true" then
            return
        end
    end
    local group = minetest.get_item_group(node.name, "command_block")
    if group > 3 then -- conditional
        local dir = minetest.facedir_to_dir(node.param2)
        local previous = vector.add(-dir, pos)
        if minetest.get_meta(previous):get_string("_result") ~= "Success" then
            if group == 6 then -- chain
                check_for_chain(pos)
            end
            return
        end
    end

    if group == 3 or group == 6 then
        local pos_string = minetest.pos_to_string(pos)
        if already_run[pos_string] then return end
        already_run[pos_string] = true
        minetest.after(0, function() already_run[pos_string] = nil end)
    end

    local command = meta:get_string("_command")
    if command ~= "" then
        local command_type, param = command:match("(%S+)%s+(.*)$")
        local def = minetest.registered_chatcommands[command_type]
        if def then
            local name = meta:get_string("_name")
            -- Other mods' commands may require <name> to be a valid player name.
            if not (better_commands and better_commands.commands[command_type]) then
                name = meta:get_string("_player")
                if name == "" then return end
            end
            local context = {
                executor = pos,
                pos = pos,
                command_block = true,
                dir = minetest.facedir_to_dir(minetest.get_node(pos).param2)
            }
            if group == 2 or group == 5 then
                local success, result_text = def.func(name, param, context)
                if success then result_text = "success" end
                meta:set_string("_result", result_text)
                minetest.get_node_timer(pos):start(tonumber(meta:get_string("_delay")) or 1)
                check_for_chain(pos)
            else
                local delay = tonumber(meta:get_string("_delay")) or 0
                if delay > 0 then
                    minetest.after(delay, function()
                        local success, result_text = def.func(name, param, context)
                        if success then result_text = "success" end
                        meta:set_string("_result", result_text)
                        check_for_chain(pos)
                    end)
                else
                    local success, result_text = def.func(name, param, context)
                    if success then result_text = "success" end
                    meta:set_string("_result", result_text)
                    check_for_chain(pos)
                end
            end
        end
    end
end

local function mesecons_activate(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("_mesecons_active", "true")
    if meta:get_string("_power") ~= "false" then
        local group = minetest.get_item_group(minetest.get_node(pos).name, "command_block")
        if group ~= 3 and group ~= 6 then
            better_command_blocks.run(pos)
        end
    end
end

local function mesecons_deactivate(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("_mesecons_active", "")
    if meta:get_string("_power") ~= "false" then
        minetest.get_node_timer(pos):stop()
    end
end

for i, command_block in pairs(command_blocks) do
    local name, desc = unpack(command_block)
    local def = {
        description = desc,
        groups = {cracky = 1, command_block = i, creative_breakable=1, mesecon_effector_off=1, mesecon_effector_on=1},
        tiles = {
            {name = "better_command_blocks_"..name.."_top.png", animation = anim},
            {name = "better_command_blocks_"..name.."_bottom.png", animation = anim},
            {name = "better_command_blocks_"..name.."_right.png", animation = anim},
            {name = "better_command_blocks_"..name.."_left.png", animation = anim},
            {name = "better_command_blocks_"..name.."_front.png", animation = anim},
            {name = "better_command_blocks_"..name.."_back.png", animation = anim},
        },
        paramtype2 = "facedir",
        on_rightclick = on_rightclick,
        on_timer = better_command_blocks.run,
        mesecons = {
            effector = {
                action_on = mesecons_activate,
                action_off = mesecons_deactivate,
                rules = mesecons_rules
            },
        },
        _mcl_blast_resistance = 3600000,
        _mcl_hardness = -1,
        can_dig = function(pos, player)
            return minetest.check_player_privs(player, "better_command_blocks")
        end,
        drop = "",
        on_place = function(itemstack, player, pointed_thing)
            if minetest.check_player_privs(player, "better_command_blocks") then
                return minetest.item_place(itemstack, player, pointed_thing)
            end
        end,
        after_place_node = function(pos, placer, itemstack, pointed_thing)
            minetest.get_meta(pos):set_string("_player", placer:get_player_name())
        end
    }
    local itemstring = "better_command_blocks:"..name.."_command_block"
    minetest.register_node(itemstring, def)
    command_block_itemstrings[i] = itemstring

    local conditional_def = table.copy(def)
    conditional_def.groups.not_in_creative_inventory = 1
    conditional_def.groups.command_block = i+3
    conditional_def.description = "Conditional "..desc
    conditional_def.tiles = {
        {name = "better_command_blocks_"..name.."_conditional_top.png", animation = anim},
        {name = "better_command_blocks_"..name.."_conditional_bottom.png", animation = anim},
        {name = "better_command_blocks_"..name.."_conditional_right.png", animation = anim},
        {name = "better_command_blocks_"..name.."_conditional_left.png", animation = anim},
        {name = "better_command_blocks_"..name.."_front.png", animation = anim},
        {name = "better_command_blocks_"..name.."_back.png", animation = anim},
    }
    itemstring = "better_command_blocks:"..name.."_command_block_conditional"
    minetest.register_node(itemstring, conditional_def)
    command_block_itemstrings[i+3] = itemstring
end

minetest.register_alias("better_command_blocks:command_block", "better_command_blocks:impulse_command_block")
minetest.register_alias("better_command_blocks:command_block_conditional", "better_command_blocks:impulse_command_block_conditional")

minetest.register_privilege("better_command_blocks", {
    description = "Allows players to use command blocks",
    give_to_singleplayer = false,
    give_to_admin = true
})