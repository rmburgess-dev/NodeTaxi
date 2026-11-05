-- Real-data multi-waypoint regression: corridors, fallback lines, and rolling
-- stability across several zone-travel targets.
local ADDON = {}
_G.NodeTaxiNS = ADDON
_G.NodeTaxiDB = nil

local playerZoneX, playerZoneY, playerZoneMap = 0.618, 0.523, 1420
local maps = assert(loadfile("tests/map_fixture.lua"))()
local children = {}
for id, info in pairs(maps) do
    children[info.parent] = children[info.parent] or {}
    children[info.parent][#children[info.parent] + 1] = { mapID = id }
end

local function frame()
    local f = {}
    function f:SetScript() end
    function f:HookScript() end
    function f:RegisterEvent() end
    function f:CreateLine() return { SetThickness=function() end, SetVertexColor=function() end, SetStartPoint=function() end, SetEndPoint=function() end, Show=function() end, Hide=function() end } end
    function f:CreateTexture() return { SetTexture=function() end, SetVertexColor=function() end, SetSize=function() end, SetPoint=function() end, Show=function() end, Hide=function() end } end
    function f:SetFrameStrata() end
    function f:SetFrameLevel() end
    function f:GetFrameLevel() return 1 end
    function f:GetWidth() return 1024 end
    function f:GetHeight() return 768 end
    function f:SetAllPoints() end
    function f:IsShown() return false end
    function f:GetMapID() return 1420 end
    return f
end
_G.WorldMapFrame = frame()
WorldMapFrame.ScrollContainer = { Child = frame() }
WorldMapFrame.IsShown = function() return false end
_G.Minimap = frame(); Minimap.IsShown = function() return false end
_G.UIParent = frame()
_G.CreateFrame = frame
_G.GetCVar = function() return "0" end
_G.GetPlayerFacing = function() return 0 end
_G.GetTime = function() return os.time() end
_G.time = os.time
_G.IsInInstance = function() return false end
_G.hooksecurefunc = function() end
_G.GetBuildInfo = function() return "1.60.1", "70790", "Nov 4 2026", 16001 end
_G.GetSpellInfo = function() return nil end
_G.GetAddOnMetadata = function() return "0.9.22" end
_G.EventRegistry = { RegisterCallback = function() end }
_G.C_Timer = { After = function(_, fn) fn() end }
_G.SlashCmdList = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.TomTom = {
    private = { GetCrazyArrowTarget = function() return nil end },
    RegisterCallback = function() end,
    AddWaypoint = function() error("unexpected waypoint") end,
    SetCrazyArrow = function() error("unexpected arrow") end,
}
local hbd = {
    GetPlayerZonePosition = function() return playerZoneX, playerZoneY, playerZoneMap end,
    GetZoneSize = function() return 1000, 1000 end,
    GetPlayerWorldPosition = function() return 0, 0, 0 end,
    GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end,
    GetZoneDistance = function() return 30 end,
    GetZoneCoordinatesFromWorldInstance = function(_, wx, wy) return wx / 1000, wy / 1000 end,
}
_G.LibStub = function(name) if name == "HereBeDragons-2.0" then return hbd end end
_G.CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
_G.C_Map = {
    GetBestMapForUnit = function() return playerZoneMap end,
    GetPlayerMapPosition = function() return { GetXY = function() return playerZoneX, playerZoneY end } end,
    GetMapInfo = function(id)
        local m = maps[id]
        return m and { name = m.name, parentMapID = m.parent, mapType = m.mapType } or nil
    end,
    GetMapChildrenInfo = function(id) return children[id] or {} end,
    GetMapRectOnMap = function() return nil end,
    GetMapInfoAtPosition = function() return nil end,
    GetMapLinksForMap = function() return nil end,
    GetMapPosFromWorldPos = function(_, v)
        local x, y = v:GetXY()
        return playerZoneMap, { GetXY = function() return x / 1000, y / 1000 end }
    end,
}
_G.C_Minimap = {
    GetViewRadius = function() return 300 end,
    GetNumTrackingTypes = function() return 2 end,
    GetTrackingInfo = function(i)
        if i == 1 then return { name = "Find Herbs", active = false } end
        return { name = "Find Minerals", active = true }
    end,
}

local function load(path) assert(loadfile(path))("NodeTaxi", ADDON) end
load("data.lua")
load("transitions.lua")
load("corridors.lua")
load("route.lua")
load("core.lua")
load("overlay.lua")
ADDON.InitDB()
ADDON.settings.kind = "auto"
ADDON.settings.allNodes = false
ADDON.settings.maxNodes = 8
ADDON.activeTracking = "ore"
ADDON.state.nodes = {}
ADDON.state.route = nil

local targets = {
    { 1429, 0.42, 0.65, "Elwynn Goldshire" },
    { 1434, 0.32, 0.29, "STV Grom'gol" },
    { 1424, 0.61, 0.20, "Hillsbrad Tarren Mill" },
    { 1425, 0.14, 0.47, "Hinterlands Aerie Peak" },
    { 1422, 0.42, 0.84, "WPL Chillwind" },
    { 1440, 0.34, 0.49, "Ashenvale Astranaar" },
    { 1446, 0.51, 0.27, "Tanaris Gadgetzan" },
    { 1452, 0.60, 0.37, "Winterspring Everlook" },
}

local failures = {}
local function pathStats(pts)
    local reversals, maxJump, length = 0, 0, 0
    local prevDx, prevDy
    for i = 2, #pts do
        local dx, dy = pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y
        local d = math.sqrt(dx * dx + dy * dy)
        length = length + d
        if d > maxJump then maxJump = d end
        if prevDx then
            local dot = dx * prevDx + dy * prevDy
            local norm = d * math.sqrt(prevDx * prevDx + prevDy * prevDy)
            if norm > 0 and dot / norm < -0.5 then
                reversals = reversals + 1
            end
        end
        prevDx, prevDy = dx, dy
    end
    return reversals, maxJump * 1000, length * 1000
end

local function check(name, ok, detail)
    if not ok then
        failures[#failures + 1] = name .. (detail and (" (" .. tostring(detail) .. ")") or "")
    end
end

for _, target in ipairs(targets) do
    playerZoneMap, playerZoneX, playerZoneY = 1420, 0.618, 0.523
    ADDON.state.dest = { map = target[1], x = target[2], y = target[3], title = target[4] }
    ADDON:ClearRoute(nil, true)
    local built = ADDON:BuildRoute(false)
    local route = ADDON.state.route
    check(target[4] .. " builds", built == true)
    check(target[4] .. " has legs", route and #(route.legs or {}) > 0)
    if route then
        local corridorLegs, fallbackLegs = 0, 0
        local totalReversals, totalYards = 0, 0
        for _, leg in ipairs(route.legs) do
            check(target[4] .. " leg has a line", leg.routePoints and #leg.routePoints >= 2,
                leg.map)
            check(target[4] .. " leg respects max",
                #(leg.nodes or {}) <= ADDON.settings.maxNodes, #(leg.nodes or {}))
            local reversals, _, legYards = pathStats(leg.routePoints or {})
            totalReversals = totalReversals + reversals
            totalYards = totalYards + legYards
            if leg.corridorPoints then corridorLegs = corridorLegs + 1 else fallbackLegs = fallbackLegs + 1 end
        end
        print(string.format("%s: legs=%d nodes=%d reversals=%d yards=%.0f",
            target[4], #route.legs, route.totalNodes or 0, totalReversals, totalYards))
        local reversalBudget = math.max(6, #route.legs * 2)
        check(target[4] .. " route stays reasonably direct",
            totalReversals <= reversalBudget,
            totalReversals .. "/" .. reversalBudget)
        if target[1] == 1429 then
            check("Elwynn is corridor-backed end to end", corridorLegs == #route.legs,
                corridorLegs .. "/" .. #route.legs)
        end
        if target[1] == 1434 then
            check("STV transport has a fallback leg", fallbackLegs >= 1, fallbackLegs)
        end
    end
end

-- Full-leg rolling stability.
playerZoneMap, playerZoneX, playerZoneY = 1421, 0.66, 0.40
ADDON.state.dest = { map = 1429, x = 0.42, y = 0.65, title = "rolling" }
ADDON:ClearRoute(nil, true)
check("rolling route builds", ADDON:BuildRoute(false) == true)
local rollingRoute = ADDON.state.route
local rollingLeg = rollingRoute and rollingRoute.legs and rollingRoute.legs[1]
check("rolling first leg is full", rollingLeg and #(rollingRoute.nodes or {}) == ADDON.settings.maxNodes,
    rollingRoute and #(rollingRoute.nodes or {}))
if rollingLeg and #(rollingRoute.nodes or {}) == ADDON.settings.maxNodes then
    local before = {}
    for _, node in ipairs(rollingRoute.nodes) do
        before[string.format("%.4f,%.4f", node.x, node.y)] = true
    end
    local changed = false
    for i = 1, #(rollingLeg.routePoints or {}), math.max(1, math.floor(#rollingLeg.routePoints / 8)) do
        playerZoneMap = rollingLeg.map
        playerZoneX, playerZoneY = rollingLeg.routePoints[i].x, rollingLeg.routePoints[i].y
        ADDON:RefreshCurrentLeg()
        local after = {}
        for _, node in ipairs(ADDON.state.route.nodes or {}) do
            after[string.format("%.4f,%.4f", node.x, node.y)] = true
        end
        for key in pairs(before) do if not after[key] then changed = true end end
        for key in pairs(after) do if not before[key] then changed = true end end
    end
    check("full rolling leg stays stable", changed == false)
end

if #failures > 0 then
    io.stderr:write("FAILURES:\n" .. table.concat(failures, "\n") .. "\n")
    os.exit(1)
end
print(string.format("multiwaypoint: %d targets, rolling stable", #targets))
