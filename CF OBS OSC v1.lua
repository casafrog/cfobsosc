

obs = obslua
local socket = require("ljsocket")
local bit = require("bit")

-- Configuration items
local version = "1.0"
local osc_server = nil
local packet_count = 0

-- Settings (with safe defaults)
local debug_print_enabled = true
local osc_interface = "0.0.0.0"
local osc_port = 12345
local polling_rate = 5

------------------------------------------------------------
-- OBS Script Lifecycle Configuration
------------------------------------------------------------
function script_description()
    return '<center><h2>CF OBS OSC Simplistic Controller</h></center>' ..
        '<h2>Version: ' .. version .. ' </h2>' ..
        '<p>' ..
        [[
        Description:
        A very simple internal OBS OSC Server that will parse an OSC packet for scene transition purposes.
        This is intended to permit OBS to be commanded by another show control system, typically in a live theatre situation.
        <p>Use Examples</p>
        <p>Scene by index: /obs/scene 3   (where /obs/scene is the command and the scene index is an integer parameter)</p>
        <p>Scene by name: /obs/scene Scene3   (where /obs/scene is the command and the scene name is a string parameter)</p>
        <p>Important: Be sure to update your preferred incoming OSC interface and port numbers to match your situation. 
        An OSC Interface address of 0.0.0.0 should bind to all interfaces, however if your situation requires it you may have to be more specific.</p>
        <p>This script depends on the inclusion of a partner script, "ljsocket.lua" by Elias Hogstvedt, so many thanks! Please place it in the same folder as this script or in your profiles obs-script folder.</p>
        <p>Please note that this script or its limited functionality might not be correct for your situation. If you require greater control or a different setup, 
        we highly recommend OSC-for-OBS by Joe Shea. For our applications, we wanted an auto-start, native and embedded, "non-adjustable" solution that did not involve
        a separate bridge application that could be accidentially closed by yhe user. To that end, we accepted the restrictions that came with a native Lua development with OBS.</p>
        ]] ..
        '</p><p>www.casafrog.com T.Hyde 2026</p>'
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "debug_print_enabled", "Debug To Log File")
    obs.obs_properties_add_text(props, "osc_interface", "OSC Incoming Interface Address:", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "osc_port", "OSC Incoming Port:", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int(props, "polling_rate", "Polling Rate (per second)", 1, 10, 1)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "debug_print_enabled", true)
    obs.obs_data_set_default_string(settings, "osc_interface", "0.0.0.0")
    obs.obs_data_set_default_string(settings, "osc_port", "12345")
    obs.obs_data_set_default_int(settings, "polling_rate", 5)
end

function script_load(settings)
    print("Script Load: OBS-OSC-CF version " .. version)
end

function script_unload()
    if osc_server ~= nil then
        print('Shutting down OSC connection')
        osc_server:close()
        osc_server = nil
    end
    obs.timer_remove(timer_callback)
end

function script_update(settings)
    debug_print_enabled = obs.obs_data_get_bool(settings, "debug_print_enabled")

    osc_interface = obs.obs_data_get_string(settings, "osc_interface")

    local port_str = obs.obs_data_get_string(settings, "osc_port")
    osc_port = tonumber(port_str) or 12345

    polling_rate = obs.obs_data_get_int(settings, "polling_rate")

    -- Validate port
    if osc_port < 1 or osc_port > 65535 then
        print("Invalid port, falling back to 12345")
        osc_port = 12345
    end

    restart_osc()
end

------------------------------------------------------------
-- Debug Helper
------------------------------------------------------------
function debug_print(msg)
    if debug_print_enabled then
        print(msg)
    end
end

------------------------------------------------------------
-- OSC Socket Creation
------------------------------------------------------------
function restart_osc()
    if osc_server ~= nil then
        osc_server:close()
        osc_server = nil
    end

    osc_server = assert(socket.create("inet", "dgram", "udp"))
    assert(osc_server:set_option("reuseaddr", 1))
    assert(osc_server:set_blocking(false))
    assert(osc_server:bind(osc_interface, osc_port))

    obs.timer_remove(timer_callback)
    obs.timer_add(timer_callback, 1000 / polling_rate)

    debug_print("Restarting on UDP Interface " .. osc_interface)
    debug_print("Restarting on UDP port " .. osc_port)
end

------------------------------------------------------------
-- OSC Parsing Helpers
------------------------------------------------------------
function read_osc_string(data, index)
    local len = #data
    local start = index

    while index <= len and data:byte(index) ~= 0 do
        index = index + 1
    end

    local str = data:sub(start, index - 1)

    index = index + (4 - ((index - start) % 4))
    return str, index
end

function read_int32(data, index)
    local b1, b2, b3, b4 = data:byte(index, index + 3)
    local val = bit.bor(
        bit.lshift(b1, 24),
        bit.lshift(b2, 16),
        bit.lshift(b3, 8),
        b4
    )
    return val, index + 4
end

function parse_osc(data)
    local index = 1

    local address
    address, index = read_osc_string(data, index)

    local types
    types, index = read_osc_string(data, index)

    if types:sub(1,1) ~= "," then
        return nil
    end

    local args = {}

    for i = 2, #types do
        local t = types:sub(i,i)

        if t == "s" then
            local str
            str, index = read_osc_string(data, index)
            table.insert(args, str)

        elseif t == "i" then
            local val
            val, index = read_int32(data, index)
            table.insert(args, val)

        else
            print("Unsupported OSC type: " .. t)
        end
    end

    return address, args
end

------------------------------------------------------------
-- OBS Operational Helpers
------------------------------------------------------------
function get_source(name)
    local src = obs.obs_get_source_by_name(name)
    if src == nil then
        print("Source not found: " .. name)
    end
    return src
end

function get_scene_by_index(index)
    local scenes = obs.obs_frontend_get_scenes()
    if scenes == nil then return nil end

    local count = obs.obs_source_list_count(scenes)

    if index < 1 or index > count then
        print("Scene index out of range: " .. index)
        obs.source_list_release(scenes)
        return nil
    end

    local scene = scenes[index]
    obs.obs_source_addref(scene)
    obs.source_list_release(scenes)

    return scene
end

function resolve_scene(arg)
    if type(arg) == "number" then
        return get_scene_by_index(arg)
    elseif type(arg) == "string" then
        return get_source(arg)
    end
    return nil
end

function set_transition(name, duration)
    local t = get_source(name)
    if t ~= nil then
        if duration ~= nil then
            obs.obs_source_set_transition_duration(t, duration)
        end
        obs.obs_frontend_set_current_transition(t)
        obs.obs_source_release(t)
        print("Transition set: " .. name)
    end
end

function set_program_scene(scene_arg)
    local s = resolve_scene(scene_arg)
    if s ~= nil then
        obs.obs_frontend_set_current_scene(s)
        obs.obs_source_release(s)
        print("Program set")
    end
end

function set_preview_scene(scene_arg)
    local s = resolve_scene(scene_arg)
    if s ~= nil then
        obs.obs_frontend_set_preview_scene(s)
        obs.obs_source_release(s)
        print("Preview set")
    end
end

function take_transition(transition_name, duration)
    local current = obs.obs_frontend_get_current_transition()

    if transition_name ~= nil then
        set_transition(transition_name, duration)
    end

    obs.obs_frontend_transition_trigger()

    if current ~= nil then
        obs.obs_frontend_set_current_transition(current)
        obs.obs_source_release(current)
    end
end

function set_scene_with_transition(scene_arg, transition_name, duration)
    local current = obs.obs_frontend_get_current_transition()

    set_transition(transition_name, duration)

    local s = resolve_scene(scene_arg)
    if s ~= nil then
        obs.obs_frontend_set_current_scene(s)
        obs.obs_source_release(s)
    end

    if current ~= nil then
        obs.obs_frontend_set_current_transition(current)
        obs.obs_source_release(current)
    end
end

------------------------------------------------------------
-- OSC Dispatcher
------------------------------------------------------------
function handle_osc(address, args)
    debug_print("OSC: " .. address)

    if address == "/obs/scene" then
        if #args >= 1 then
            set_program_scene(args[1])
        end
--[[
    elseif address == "/obs/scene/transition" then
        if #args >= 2 then
            local duration = (#args >= 3 and type(args[3]) == "number") and args[3] or nil
            set_scene_with_transition(args[1], args[2], duration)
        end

    elseif address == "/obs/preview" then
        if #args >= 1 then
            set_preview_scene(args[1])
        end

    elseif address == "/obs/take" then
        local transition = (#args >= 1 and type(args[1]) == "string") and args[1] or nil
        local duration = (#args >= 2 and type(args[2]) == "number") and args[2] or nil
        take_transition(transition, duration)

    elseif address == "/obs/transition" then
        if #args >= 1 then
            local duration = (#args >= 2 and type(args[2]) == "number") and args[2] or nil
            set_transition(args[1], duration)
        end

    elseif address == "/obs/cut" then
        take_transition("Cut", 0)

    elseif address == "/obs/fade" then
        take_transition("Fade", nil)
]]
    else
        debug_print("Unhandled OSC address: " .. address)
    end
end

------------------------------------------------------------
-- Timer Handler
------------------------------------------------------------
function timer_callback()
    packet_count = packet_count + 1
    debug_print("OSC Polling: " .. packet_count)

    repeat
        local data, status = osc_server:receive_from()

        if data then
            debug_print("REceived a packet: " .. data)
            local address, args = parse_osc(data)

            if address then
                handle_osc(address, args)
            else
                debug_print("Invalid OSC packet")
            end

        elseif status ~= "timeout" then
            error(status)
        end

    until data == nil
end