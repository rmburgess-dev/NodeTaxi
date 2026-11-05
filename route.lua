--[[--------------------------------------------------------------------------
    NodeTaxi - route planning
    --------------------------------------------------------------------------
    Pure Lua. No WoW API in this file, so the planner can be unit tested
    outside the game (see tests/route_spec.lua).

    The planner works on one map ("zone") at a time:
      * drop nodes that are not roughly between the player and the target
      * order the rest with nearest neighbour + 2-opt
      * drop nodes until the route fits the node budget and the detour budget

    All distances are in yards. Callers pass normalised (0..1) map
    coordinates plus the map size in yards.
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
ns = ns or _G.NodeTaxiNS
if not ns then
    ns = {}
    _G.NodeTaxiNS = ns
end

local Route = {}
ns.Route = Route

local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max

local function Distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

local function PathLength(path)
    local total = 0
    for i = 2, #path do
        total = total + Distance(path[i - 1], path[i])
    end
    return total
end

-- Classic nearest neighbour over the candidate set, ending at the target.
local function NearestNeighbour(startPoint, destPoint, points)
    local remaining, path = {}, { startPoint }
    for i = 1, #points do
        remaining[i] = points[i]
    end

    local current = startPoint
    while #remaining > 0 do
        local best, bestDist = 1, Distance(current, remaining[1])
        for i = 2, #remaining do
            local d = Distance(current, remaining[i])
            if d < bestDist then
                best, bestDist = i, d
            end
        end
        current = table.remove(remaining, best)
        path[#path + 1] = current
    end

    path[#path + 1] = destPoint
    return path
end

-- 2-opt on an open path. path[1] (player) and path[#path] (target) stay put.
local function TwoOpt(path)
    local n = #path
    if n < 4 then
        return path
    end

    local improved, guard = true, 0
    while improved and guard < 50 do
        improved, guard = false, guard + 1
        for i = 2, n - 2 do
            for j = i + 1, n - 1 do
                local a, b, c, d = path[i - 1], path[i], path[j], path[j + 1]
                local delta = Distance(a, c) + Distance(b, d) - Distance(a, b) - Distance(c, d)
                if delta < -0.01 then
                    local lo, hi = i, j
                    while lo < hi do
                        path[lo], path[hi] = path[hi], path[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    improved = true
                end
            end
        end
    end

    return path
end

local function Solve(startPoint, destPoint, points)
    return TwoOpt(NearestNeighbour(startPoint, destPoint, points))
end

--[[
    opts = {
        start  = { x = 0..1, y = 0..1 },
        dest   = { x = 0..1, y = 0..1 },
        nodes  = array of { x = 0..1, y = 0..1, ... },
        width  = map width in yards,
        height = map height in yards,
        corridor   = half width of the search corridor, yards (default 300)
        maxNodes   = nodes the route may visit (default 8)
        detour     = allowed length / direct length (default 1.8)
        minDirect  = direct distance floor used for the detour budget (default 200)
        maxCandidates = planner cap before pruning (default 24)
    }

    returns plan or nil, error
    plan = {
        nodes   = ordered node refs (same tables as opts.nodes),
        length  = route length in yards,
        direct  = player -> target distance,
        budget  = detour budget that was applied,
        inCorridor, eligible, dropped, corridor,
    }
]]
function Route.Plan(opts)
    if type(opts) ~= "table" then
        return nil, "no options"
    end

    local start, dest = opts.start, opts.dest
    local nodes = opts.nodes or {}
    local width, height = opts.width, opts.height
    if not (start and dest and start.x and start.y and dest.x and dest.y) then
        return nil, "missing start/destination"
    end
    if not (width and height and width > 0 and height > 0) then
        return nil, "map size unknown"
    end

    local corridor = opts.corridor or 300
    local maxNodes = max(1, opts.maxNodes or 8)
    local detour = max(1, opts.detour or 1.8)
    local minDirect = opts.minDirect or 200
    local maxCandidates = max(maxNodes, opts.maxCandidates or 24)

    local sx, sy = start.x * width, start.y * height
    local ex, ey = dest.x * width, dest.y * height

    local dx, dy = ex - sx, ey - sy
    local direct = sqrt(dx * dx + dy * dy)

    -- Standing on the target: nothing sensible to plan.
    if direct < 1 then
        return {
            nodes = {},
            length = 0,
            direct = direct,
            budget = 0,
            inCorridor = 0,
            eligible = 0,
            dropped = #nodes,
            corridor = corridor,
        }
    end

    local ux, uy = dx / direct, dy / direct

    -- Corridor filter: project every node on the straight player->target
    -- line, keep the ones in front of the player and close enough to it.
    local inCorridor = 0
    local candidates = {}
    for i = 1, #nodes do
        local node = nodes[i]
        if node.x and node.y then
            local nx, ny = node.x * width, node.y * height
            local rx, ry = nx - sx, ny - sy
            local dxToDest, dyToDest = nx - ex, ny - ey

            -- Ignore nodes under the player or on the target itself.
            if (rx * rx + ry * ry) > 4 and (dxToDest * dxToDest + dyToDest * dyToDest) > 4 then
                local t = (rx * ux + ry * uy) / direct
                if t >= 0 and t <= 1 then
                    local perp = abs(rx * -uy + ry * ux)
                    if perp <= corridor then
                        inCorridor = inCorridor + 1
                        candidates[#candidates + 1] = {
                            x = nx, y = ny,
                            src = node,
                            t = t, perp = perp,
                        }
                    end
                end
            end
        end
    end

    -- Keep the planner cheap when a zone has hundreds of nodes: the ones
    -- closest to the centre line are the most likely to survive pruning.
    if #candidates > maxCandidates then
        table.sort(candidates, function(a, b)
            if a.perp == b.perp then
                return a.t < b.t
            end
            return a.perp < b.perp
        end)
        for i = #candidates, maxCandidates + 1, -1 do
            candidates[i] = nil
        end
    end
    local eligible = #candidates

    local startPoint = { x = sx, y = sy }
    local destPoint = { x = ex, y = ey }
    local budget = max(direct, minDirect) * detour

    local selected = candidates
    local path = Solve(startPoint, destPoint, selected)
    local length = PathLength(path)

    -- Drop the node that costs the most until both budgets are met.
    while (#selected > maxNodes) or (length > budget and #selected > 0) do
        local bestIndex, bestPath, bestLength
        for i = 1, #selected do
            local trial = {}
            for k = 1, #selected do
                if k ~= i then
                    trial[#trial + 1] = selected[k]
                end
            end

            local trialPath = Solve(startPoint, destPoint, trial)
            local trialLength = PathLength(trialPath)
            if not bestLength or trialLength < bestLength then
                bestIndex, bestPath, bestLength = i, trialPath, trialLength
            end
        end

        if not bestIndex then
            break
        end
        table.remove(selected, bestIndex)
        path, length = bestPath, bestLength
    end

    local ordered = {}
    for i = 2, #path - 1 do
        ordered[#ordered + 1] = path[i].src
    end

    return {
        nodes = ordered,
        length = length,
        direct = direct,
        budget = budget,
        inCorridor = inCorridor,
        eligible = eligible,
        dropped = inCorridor - #selected,
        corridor = corridor,
    }
end

--[[
    Normalise a point from mapID into topMapID's 0..1 space.

    getRect(uiMapID, topUiMapID) returns minX, maxX, minY, maxY and
    getInfo(uiMapID) returns { parentMapID = ... } (the C_Map functions).
    The direct lookup is tried first (it handles any ancestor on modern
    clients); otherwise the parent chain is composed step by step.
]]
function Route.MapPointTo(mapID, x, y, topMapID, getRect, getInfo)
    if mapID == topMapID then
        return x, y
    end
    if not (getRect and getInfo) then
        return nil
    end

    local left, right, bottom, top = getRect(mapID, topMapID)
    if left then
        return left + x * (right - left), bottom + y * (top - bottom)
    end

    local current, cx, cy = mapID, x, y
    for _ = 1, 12 do
        local info = getInfo(current)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then
            return nil
        end

        local pl, pr, pb, pt = getRect(current, parent)
        if not pl then
            return nil
        end

        cx, cy = pl + cx * (pr - pl), pb + cy * (pt - pb)
        current = parent
        if current == topMapID then
            return cx, cy
        end
    end

    return nil
end

Route.Distance = Distance
Route.PathLength = PathLength
