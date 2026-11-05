-- Unit tests for the pure Lua route planner.
-- Run from the addon folder: lua tests/route_spec.lua

package.path = package.path .. ";./?.lua"

_G.NodeTaxiNS = {}
dofile("route.lua")
local Route = _G.NodeTaxiNS.Route
assert(Route, "route.lua did not define ns.Route")

local failures, checks = 0, 0

local function check(name, condition, detail)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print(string.format("FAIL %s%s", name, detail and (" - " .. tostring(detail)) or ""))
    end
end

local function approx(actual, expected, epsilon, name)
    epsilon = epsilon or 0.01
    check(name, actual and math.abs(actual - expected) <= epsilon,
        string.format("expected %.3f, got %s", expected, tostring(actual)))
end

local function node(x, y)
    return { x = x, y = y, kind = "herb" }
end

local function orderedAscending(nodes)
    for i = 2, #nodes do
        if nodes[i].y < nodes[i - 1].y then
            return false
        end
    end
    return true
end

-- 1. Corridor filter + ordering ------------------------------------------
do
    local nodes = {
        node(0.1, 0.3),
        node(0.5, 0.5), -- 400 yd off the line, outside a 300 yd corridor
        node(0.1, 0.6),
        node(0.1, 0.8),
    }
    local plan = Route.Plan({
        start = { x = 0.1, y = 0.1 },
        dest = { x = 0.1, y = 0.9 },
        nodes = nodes,
        width = 1000, height = 1000,
        corridor = 300,
        maxNodes = 10,
        detour = 5,
    })

    check("corridor plan exists", plan ~= nil)
    check("corridor keeps 3 nodes", plan and #plan.nodes == 3, plan and #plan.nodes)
    check("corridor counts 3", plan and plan.inCorridor == 3, plan and plan.inCorridor)
    check("corridor orders along the path", plan and orderedAscending(plan.nodes))
    approx(plan and plan.direct, 800, 0.01, "direct distance")
    approx(plan and plan.length, 800, 0.51, "collinear route length")
end

-- 2. Node budget ----------------------------------------------------------
do
    local nodes = {}
    for i = 1, 8 do
        nodes[#nodes + 1] = node(0.1, 0.1 + i * 0.08)
    end
    local plan = Route.Plan({
        start = { x = 0.1, y = 0.1 },
        dest = { x = 0.1, y = 0.9 },
        nodes = nodes,
        width = 1000, height = 1000,
        corridor = 300,
        maxNodes = 3,
        detour = 5,
    })

    check("budget plan exists", plan ~= nil)
    check("budget caps nodes", plan and #plan.nodes == 3, plan and #plan.nodes)
    check("budget keeps order", plan and orderedAscending(plan.nodes))
end

-- 3. Detour budget --------------------------------------------------------
do
    local nodes = {}
    for i = 1, 7 do
        local side = (i % 2 == 0) and 0.38 or -0.18
        nodes[#nodes + 1] = node(0.1 + side, 0.15 + i * 0.1)
    end

    local plan = Route.Plan({
        start = { x = 0.1, y = 0.1 },
        dest = { x = 0.1, y = 0.9 },
        nodes = nodes,
        width = 1000, height = 1000,
        corridor = 300,
        maxNodes = 10,
        detour = 1.05,
    })

    check("detour plan exists", plan ~= nil)
    check("detour respects budget",
        plan and (#plan.nodes == 0 or plan.length <= plan.budget + 1e-6),
        plan and string.format("length %.1f budget %.1f", plan.length, plan.budget))
end

-- 4. Nodes behind the player are ignored ----------------------------------
do
    local plan = Route.Plan({
        start = { x = 0.1, y = 0.5 },
        dest = { x = 0.1, y = 0.9 },
        nodes = { node(0.1, 0.2), node(0.1, 0.7) },
        width = 1000, height = 1000,
        corridor = 300,
        maxNodes = 10,
        detour = 5,
    })

    check("behind plan exists", plan ~= nil)
    check("behind node dropped", plan and #plan.nodes == 1, plan and #plan.nodes)
    approx(plan and plan.nodes[1].y, 0.7, 1e-9, "only forward node kept")
end

-- 5. Degenerate start == destination --------------------------------------
do
    local plan = Route.Plan({
        start = { x = 0.5, y = 0.5 },
        dest = { x = 0.5, y = 0.5 },
        nodes = { node(0.5, 0.6) },
        width = 1000, height = 1000,
        corridor = 300,
        maxNodes = 8,
        detour = 1.8,
    })

    check("degenerate plan exists", plan ~= nil)
    check("degenerate has no nodes", plan and #plan.nodes == 0)
    approx(plan and plan.length, 0, 1e-9, "degenerate length")
end

-- 6. Empty node set -------------------------------------------------------
do
    local plan = Route.Plan({
        start = { x = 0.1, y = 0.1 },
        dest = { x = 0.1, y = 0.9 },
        nodes = {},
        width = 1000, height = 1000,
    })

    check("empty plan exists", plan ~= nil)
    check("empty plan has no nodes", plan and #plan.nodes == 0)
    approx(plan and plan.length, 800, 0.01, "empty route length equals direct")
end

-- 7. Map projection -------------------------------------------------------
do
    local rects = {
        ["1429:1419"] = { 0.2, 0.6, 0.3, 0.7 },
        ["1430:1429"] = { 0.0, 0.5, 0.0, 1.0 },
    }
    local parents = {
        [1429] = { parentMapID = 1419 },
        [1430] = { parentMapID = 1429 },
        [1419] = { parentMapID = 0 },
    }

    local function getRect(a, b)
        local rect = rects[a .. ":" .. b]
        if rect then
            return rect[1], rect[2], rect[3], rect[4]
        end
        return nil
    end

    local function getInfo(id)
        return parents[id]
    end

    local x, y = Route.MapPointTo(1429, 0.5, 0.5, 1419, getRect, getInfo)
    approx(x, 0.4, 1e-9, "zone -> continent x")
    approx(y, 0.5, 1e-9, "zone -> continent y")

    local sx, sy = Route.MapPointTo(1429, 0.25, 0.75, 1429, getRect, getInfo)
    approx(sx, 0.25, 1e-9, "same map x")
    approx(sy, 0.75, 1e-9, "same map y")

    -- The direct 1430 -> 1419 rect is deliberately absent, so the function
    -- has to compose 1430 -> 1429 -> 1419.
    local gx, gy = Route.MapPointTo(1430, 0.5, 0.5, 1419, getRect, getInfo)
    approx(gx, 0.3, 1e-9, "grandchild composition x")
    approx(gy, 0.5, 1e-9, "grandchild composition y")

    -- Map y is top-down. The top edge of the grandchild (y=0) must land on
    -- the parent's minY (0.3), not on maxY (0.7), and vice versa.
    local _, topY = Route.MapPointTo(1430, 0, 0, 1419, getRect, getInfo)
    local _, bottomY = Route.MapPointTo(1430, 1, 1, 1419, getRect, getInfo)
    approx(topY, 0.3, 1e-9, "top edge uses minY")
    approx(bottomY, 0.7, 1e-9, "bottom edge uses maxY")

    local nx = Route.MapPointTo(1430, 0.5, 0.5, 1419, nil, nil)
    check("projection without accessors returns nil", nx == nil)
end

-- 8. Route never revisits the target as a node ----------------------------
do
    local plan = Route.Plan({
        start = { x = 0.1, y = 0.1 },
        dest = { x = 0.1, y = 0.9 },
        nodes = { node(0.1, 0.9), node(0.1, 0.1), node(0.1, 0.5) },
        width = 1000, height = 1000,
        corridor = 300,
        maxNodes = 8,
        detour = 5,
    })

    check("node on target ignored", plan and #plan.nodes == 1, plan and #plan.nodes)
end


print(string.format("%d checks, %d failure(s)", checks, failures))
if failures > 0 then
    os.exit(1)
end
