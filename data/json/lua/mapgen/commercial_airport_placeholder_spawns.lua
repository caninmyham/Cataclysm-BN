local MARKER_REPLACEMENTS = {
    airport_commercial_airliner_marker = "commercial_airliner",
    airport_commercial_airliner_cargo_marker = "commercial_airliner_cargo"
}

-- Both large aircraft use a 41x41 blueprint with origin { x = 32, y = 20 }.
local AIRCRAFT_BOUNDS = {
    left = 32,
    right = 8,
    up = 20,
    down = 20
}

local failure_message_shown = false

local function roll_aircraft_status()
    local roll = math.random(1, 100)

    -- 50% perfect, 40% damaged, 10% wrecked.
    if roll <= 50 then
        return 0
    elseif roll <= 90 then
        return -1
    else
        return 1
    end
end

local function aircraft_fits_loaded_map(map, pos)
    local size = map:get_map_size()

    return pos.x - AIRCRAFT_BOUNDS.left >= 0
       and pos.x + AIRCRAFT_BOUNDS.right < size
       and pos.y - AIRCRAFT_BOUNDS.up >= 0
       and pos.y + AIRCRAFT_BOUNDS.down < size
end

local function report_failure(text)
    -- Keep this INFO rather than log_error: log_error deliberately emits a
    -- full C++/Lua backtrace, which obscures the actual native crash boundary.
    gdebug.log_info("airport aircraft replacement FAILED: " .. text)

    if not failure_message_shown then
        gapi.add_msg("Airport aircraft replacement failed; check debug.log.")
        failure_message_shown = true
    end
end

local function try_replace_airport_airliners()
    local map = gapi.get_map()

    -- Replace at most one marker per hook invocation.  replace_vehicle mutates
    -- the live vehicle collection, so we immediately return after attempting it.
    for _, vehicle in ipairs(map:get_vehicles()) do
        local marker_id = vehicle:type()
        local replacement_id = MARKER_REPLACEMENTS[marker_id]

        if replacement_id then
            local pos = vehicle:pos()

            if not aircraft_fits_loaded_map(map, pos) then
                return
            end

            local status = roll_aircraft_status()

            gdebug.log_info(
                "airport aircraft replacement: attempting "
                .. marker_id .. " -> " .. replacement_id
                .. " at (" .. tostring(pos.x) .. "," .. tostring(pos.y) .. ")"
                .. " with status " .. tostring(status)
            )

            -- The wrapper is safe here because this function does not continue
            -- iterating after replacement.  This also avoids the transient
            -- re-resolution failure seen with the position overload.
            local ok, replaced = pcall(function()
                return map:replace_vehicle(vehicle, replacement_id, {
                    status = status
                })
            end)

            if not ok then
                report_failure(
                    marker_id .. " -> " .. replacement_id
                    .. " at (" .. tostring(pos.x) .. "," .. tostring(pos.y) .. ")"
                    .. " threw Lua/binding error: " .. tostring(replaced)
                )
            elseif not replaced then
                report_failure(
                    marker_id .. " -> " .. replacement_id
                    .. " at (" .. tostring(pos.x) .. "," .. tostring(pos.y) .. ")"
                    .. " returned false"
                )
            else
                gdebug.log_info(
                    "airport aircraft replacement: "
                    .. marker_id .. " -> " .. replacement_id
                    .. " succeeded at (" .. tostring(pos.x) .. "," .. tostring(pos.y) .. ")"
                    .. " with status " .. tostring(status)
                )
            end

            return
        end
    end
end

local function add_hook(name, spec)
    local ok, err = pcall(function()
        game.add_hook(name, spec)
    end)

    if not ok then
        gdebug.log_info(
            "airport aircraft replacement: hook unavailable: "
            .. tostring(name) .. " (" .. tostring(err) .. ")"
        )
    end
end

add_hook("on_game_started", function()
    try_replace_airport_airliners()
end)

add_hook("on_game_load", function()
    try_replace_airport_airliners()
end)

-- One movement hook is sufficient: every player step scans every vehicle in
-- the currently loaded map/reality bubble.
add_hook("on_player_try_move", {
    priority = -100,
    fn = function()
        try_replace_airport_airliners()
        return true
    end
})
