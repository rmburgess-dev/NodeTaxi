--[[
    Headless smoke test: loads the addon with a tiny WoW API stub, runs the
    login path, builds a route, and exercises every slash command. Catches
    nil-global mistakes and state bugs that plain syntax checks miss.
    Run from the addon folder: lua tests/load_spec.lua
]]

local ADDON = {}
_G.NodeTaxiNS = ADDON
_G.NodeTaxiDB = nil

local frames = {}
local timers = {}
local linesCreated = 0
local messages = {}
local tomtomCallbacks = {}
local currentUid = nil
local addWaypointCalls = 0

local function newRegion()
    local region = {}
    function region:SetTexture() end
    function region:SetThickness() end
    function region:SetVertexColor() end
    function region:SetStartPoint() end
    function region:SetEndPoint() end
    function region:SetSize() end
    function region:ClearAllPoints() end
    function region:SetPoint() end
    function region:SetRotation() end
    function region:IsShown() return self.shown ~= false end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    return region
end

local function newFrame()
    local frame = newRegion()
    frame.events = {}
    frame.scripts = {}
    frame.level = 1
    frame.width = 1024
    frame.height = 768
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:RegisterEvent(name) self.events[name] = true; return true end
    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:GetFrameLevel() return self.level end
    function frame:HookScript(name, fn) self.scripts[name] = fn end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:CreateLine() linesCreated = linesCreated + 1; return newRegion() end
    function frame:CreateTexture() return newRegion() end
    function frame:GetMapID() return 1429 end
    frames[#frames + 1] = frame
    return frame
end

local playerZoneX, playerZoneY = 0.5, 0.5
local playerZoneMap = 1429

local hbd = {
    GetPlayerZonePosition = function() return playerZoneX, playerZoneY, playerZoneMap end,
    GetZoneSize = function() return 1000, 1000 end,
    GetPlayerWorldPosition = function() return 0, 0, 0 end,
    GetWorldCoordinatesFromZone = function(_, x, y) return x * 1000, y * 1000, 0 end,
    GetZoneDistance = function() return 30 end,
    GetZoneCoordinatesFromWorldInstance = function(_, worldX, worldY, instance, zone)
        if zone == 1420 and worldX < 500 then
            return worldX / 1000, worldY / 1000
        end
        if zone == 1429 and worldX >= 500 then
            return worldX / 1000, worldY / 1000
        end
        return nil
    end,
}

_G.CreateVector2D = function(x, y)
    return { GetXY = function() return x, y end }
end

_G.LibStub = function(name)
    if name == "HereBeDragons-2.0" then
        return hbd
    end
    return nil
end

_G.C_Map = {
    GetBestMapForUnit = function() return playerZoneMap end,
    GetPlayerMapPosition = function()
        return { GetXY = function() return playerZoneX, playerZoneY end }
    end,
    GetMapInfo = function(id)
        if id == 1429 then
            return { name = "Elwynn Forest", parentMapID = 1419, mapType = 3 }
        end
        if id == 1420 then
            return { name = "Tirisfal Glades", parentMapID = 1419, mapType = 3 }
        end
        if id == 2482 then
            return { name = "Mount Hyjal", parentMapID = 1414, mapType = 3 }
        end
        return { name = "Eastern Kingdoms", parentMapID = 0, mapType = 2 }
    end,
    GetMapRectOnMap = function(child, parent)
        if parent == 1419 and child == 1420 then
            return 0.0, 0.5, 0.0, 1.0
        end
        if parent == 1419 and child == 1429 then
            return 0.5, 1.0, 0.0, 1.0
        end
        return nil
    end,
    GetMapChildrenInfo = function(mapID)
        if mapID == 1419 then
            return { { mapID = 1420 }, { mapID = 1429 } }
        end
        return {}
    end,
    GetMapInfoAtPosition = function(mapID, x, y)
        if mapID == 1419 then
            if x < 0.5 then
                return { mapID = 1420, mapType = 3 }
            end
            return { mapID = 1429, mapType = 3 }
        end
        return nil
    end,
    GetMapPosFromWorldPos = function(instance, vector)
        local x, y = vector:GetXY()
        if x < 500 then
            return 1420, { GetXY = function() return x / 1000, y / 1000 end }
        end
        return 1429, { GetXY = function() return x / 1000, y / 1000 end }
    end,
}

local trackingTest = nil
_G.C_Minimap = {
    GetViewRadius = function() return 300 end,
    GetNumTrackingTypes = function() return 2 end,
    GetTrackingInfo = function(i)
        if i == 1 then
            return { name = "Find Herbs", active = trackingTest == "herb" }
        end
        return { name = "Find Minerals", active = trackingTest == "ore" }
    end,
}

_G.WorldMapFrame = newFrame()
WorldMapFrame.ScrollContainer = { Child = newFrame() }
WorldMapFrame.IsShown = function() return false end
WorldMapFrame.GetMapID = function() return 1429 end

_G.Minimap = newFrame()
Minimap.IsShown = function() return true end
Minimap.GetMaskTexture = function() return nil end

_G.UIParent = newFrame()
_G.CreateFrame = function()
    return newFrame()
end

_G.GetCVar = function() return "0" end
_G.GetPlayerFacing = function() return 0 end
local fakeTime = 0
_G.GetTime = function() fakeTime = fakeTime + 1; return fakeTime end
_G.time = os.time
_G.IsInInstance = function() return false end
_G.hooksecurefunc = function() end
_G.GetBuildInfo = function() return "1.60.1", "70790", "Nov 4 2026", 16001 end
_G.GetSpellInfo = function(id)
    if id == 2366 then return "Herb Gathering" end
    if id == 2575 then return "Mining" end
    if id == 12345 then return "Gather Herbs" end
    if id == 2383 then return "Find Herbs" end
    if id == 2580 then return "Find Minerals" end
    return nil
end

_G.EventRegistry = { RegisterCallback = function() end }
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = fn end }
_G.SlashCmdList = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }

_G.TomTom = {
    private = {
        GetCrazyArrowTarget = function()
            return currentUid
        end,
    },
    RegisterCallback = function(_, event, fn)
        tomtomCallbacks[event] = fn
    end,
    AddWaypoint = function()
        addWaypointCalls = addWaypointCalls + 1
        error("NodeTaxi must never add TomTom waypoints")
    end,
    SetCrazyArrow = function()
        error("NodeTaxi must never move the TomTom arrow")
    end,
}

local function loadAddonFile(path)
    local chunk = assert(loadfile(path))
    chunk("NodeTaxi", ADDON)
end

loadAddonFile("transitions.lua")
loadAddonFile("corridors.lua")
loadAddonFile("route.lua")
loadAddonFile("core.lua")
loadAddonFile("overlay.lua")

assert(ADDON.Route, "route module missing")
assert(ADDON.BuildRoute, "core did not load")

-- Find the driver frame (the one that registered addon events).
local driver
for _, frame in ipairs(frames) do
    if frame.events and frame.events["UNIT_SPELLCAST_SUCCEEDED"] then
        driver = frame
        break
    end
end
assert(driver, "driver frame not found")

local function fire(event, ...)
    assert(driver.scripts.OnEvent, "driver has no OnEvent")
    driver.scripts.OnEvent(driver, event, ...)
end

local function runTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do
        fn()
    end
end

local failures = 0
local checks = 0
local function check(name, condition, detail)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL " .. name .. (detail and (" - " .. tostring(detail)) or ""))
    end
end

-- Login ------------------------------------------------------------------
fire("PLAYER_LOGIN")
check("login created DB", _G.NodeTaxiDB ~= nil)
check("login registered TomTom callback", tomtomCallbacks.ArrowTargetChanged ~= nil)

-- A node is learned from a real gather cast.
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2366)
check("gather cast stored a node", ADDON:NodeCount(1429) == 1, ADDON:NodeCount(1429))

-- A spell the client uses but the addon does not know yet can be taught by
-- hand, then it is captured like the built-in Herb Gathering/Mining spells.
local slashEarly = _G.SlashCmdList["NODETAXI"]
slashEarly("learn herb 12345")
playerZoneX, playerZoneY = 0.5, 0.56
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 12345)
playerZoneX, playerZoneY = 0.5, 0.5
check("learned spell captured a node", ADDON:NodeCount(1429) == 2, ADDON:NodeCount(1429))

-- Manual nodes along the path.
ADDON:AddNode(1429, 0.50, 0.62, "herb")
ADDON:AddNode(1429, 0.52, 0.74, "ore")
ADDON:AddNode(1429, 0.51, 0.86, "herb")
check("manual nodes stored", ADDON:NodeCount(1429) == 5, ADDON:NodeCount(1429))

-- The TomTom arrow points somewhere in the same zone.
currentUid = { 1429, 0.5, 0.9, title = "Test target" }
fire("PLAYER_ENTERING_WORLD")
if tomtomCallbacks.ArrowTargetChanged then
    tomtomCallbacks.ArrowTargetChanged("ArrowTargetChanged", currentUid)
end
runTimers()

check("destination read from TomTom", ADDON.state.dest ~= nil)
check("route built automatically", ADDON.state.route ~= nil)

if ADDON.state.route then
    local route = ADDON.state.route
    check("route has nodes", #route.nodes >= 1, #route.nodes)
    check("route ends at the target", route.dest and math.abs(route.dest.y - 0.9) < 1e-9)
    check("route length is sane", route.plan.length >= route.plan.direct)
end

-- Draw both overlays; must not throw.
ADDON:RedrawWorld()
ADDON:RedrawMinimap()
check("world overlay created", ADDON:OverlayDebugInfo().world ~= "not created")

-- Same route with the world map open, first on the zone map and then on the
-- continent map (which exercises GetMapRectOnMap projection).
WorldMapFrame.IsShown = function() return true end
WorldMapFrame.GetMapID = function() return 1429 end
ADDON:RedrawWorld()
local zoneLines = linesCreated
check("world overlay drew dashes on the zone map", zoneLines > 0, zoneLines)

WorldMapFrame.GetMapID = function() return 1419 end
C_Map.GetMapRectOnMap = function(a, b)
    if a == 1429 and b == 1419 then
        return 0.2, 0.6, 0.3, 0.7
    end
    return nil
end
ADDON:RedrawWorld()
check("world overlay survives continent projection", linesCreated >= zoneLines)

-- Force every node into ring mode; this exercises the hollow-ring drawing
-- path on both overlays (the center itself must stay empty).
_G.NodeTaxiDB.settings.ring = 1000
WorldMapFrame.GetMapID = function() return 1429 end
ADDON:RedrawWorld()
ADDON:RedrawMinimap()
check("ring markers draw without error", true)
_G.NodeTaxiDB.settings.ring = 100

-- World-map canvas conversion must not flip y: y=0 is the north/top edge.
local cx, cy = ADDON:MapPointToCanvas(1429, 0.5, 0.2, 1429, 100, 50)
check("canvas x conversion", cx == 50, cx)
check("canvas top edge stays at the top", cy == 10, cy)
local _, cyBottom = ADDON:MapPointToCanvas(1429, 0.5, 0.8, 1429, 100, 50)
check("canvas bottom edge stays at the bottom", cyBottom == 40, cyBottom)

-- Route keeps re-evaluating from the current position.
if ADDON.state.route then
    playerZoneX, playerZoneY = 0.5, 0.56
    local replanned = ADDON:ReplanFromCurrent(false)
    check("replan succeeds", replanned == true)
    check("replan resets next index", ADDON.state.route.index == 1)
    check("replan keeps nodes", ADDON.state.route and #ADDON.state.route.nodes > 0)
    playerZoneX, playerZoneY = 0.5, 0.5
end

-- Re-planning must not reintroduce a node that was already passed.
if ADDON.state.route and #ADDON.state.route.nodes >= 2 then
    local firstNode = ADDON.state.route.nodes[1]
    ADDON.state.route.index = 2
    ADDON:ReplanFromCurrent(false)
    local reintroduced = false
    for _, node in ipairs(ADDON.state.route.nodes) do
        if node == firstNode then reintroduced = true end
    end
    check("replan excludes consumed nodes", reintroduced == false)
    ADDON.state.route.index = 1
end

-- Walking onto the next node advances the route.
if ADDON.state.route then
    local route = ADDON.state.route
    local before = route.index
    local initialCount = #route.nodes
    playerZoneX, playerZoneY = route.nodes[before].x, route.nodes[before].y
    ADDON:Tick()
    check("tick consumes the reached node",
        ADDON.state.route == nil
            or ADDON.state.route.index > before
            or #ADDON.state.route.nodes < initialCount)
    playerZoneX, playerZoneY = 0.5, 0.5
end

-- Slash commands ---------------------------------------------------------
local slash = _G.SlashCmdList["NODETAXI"]
assert(slash, "slash command not registered")
slash("debug")
slash("nodes")
slash("dest")
slash("preview")
check("preview route active", ADDON.state.route and ADDON.state.route.preview == true)
slash("stop")
check("stop cleared route", ADDON.state.route == nil)
slash("auto off")
slash("width 250")
slash("max 5")
slash("detour 2.0")
slash("arrive 20")
slash("replan 40")
check("replan setting applied", _G.NodeTaxiDB.settings.replan == 40, _G.NodeTaxiDB.settings.replan)
slash("ring 120")
check("ring setting applied", _G.NodeTaxiDB.settings.ring == 120, _G.NodeTaxiDB.settings.ring)
slash("ring 0")
check("ring can be disabled", _G.NodeTaxiDB.settings.ring == 0)
slash("ring 100")
slash("here ore")
check("here stored a node", ADDON:NodeCount(1429) == 6, ADDON:NodeCount(1429))

slash("near 50")
local nearHeader = false
for i = math.max(1, #messages - 12), #messages do
    if messages[i]:find("known node", 1, true) then nearHeader = true end
end
check("near lists known nodes", nearHeader)

slash("validate")
local validatePrinted = false
for i = math.max(1, #messages - 20), #messages do
    if messages[i]:find("validate", 1, true) then validatePrinted = true end
end
check("validate prints a result", validatePrinted)
check("log has persisted entries", #_G.NodeTaxiDB.log > 0, #_G.NodeTaxiDB.log)

slash("log 10")
local logHeader = false
for i = math.max(1, #messages - 30), #messages do
    if messages[i]:find("entries; last", 1, true) then logHeader = true end
end
check("log command prints entries", logHeader)

slash("log chat off")
check("log chat can be disabled", ADDON.settings.logChat == false)
slash("log chat on")
check("log chat can be re-enabled", ADDON.settings.logChat == true)

slash("kind ore")
local kinds = {}
for _, node in ipairs(ADDON:NodeListForMap(1429)) do
    kinds[node.kind] = true
end
check("kind filter keeps ore", kinds.ore == true)
check("kind filter drops herbs", kinds.herb == nil)
slash("kind both")
slash("skip")        -- no route: should just print
slash("bogus")
slash("clear")       -- without yes: no deletion
check("clear needs confirmation", ADDON:NodeCount(1429) == 6)
slash("clear yes")
check("clear yes wiped nodes", ADDON:NodeCount(nil) == 0)

-- GatherMate2 import: two herb keys and one ore key in Elwynn Forest.
-- 5000500000 => 50.00, 50.00; 5000620000 => 50.00, 62.00;
-- 5200560000 => 52.00, 56.00.
_G.GatherMate2HerbDB = {
    [1429] = {
        [5000500000] = 401,
        [5000620000] = 402,
        [12345678901] = 401, -- x > 1, must be rejected
    },
}
_G.GatherMate2MineDB = {
    [1429] = { [5200560000] = 201 },
}
local dx, dy = ADDON.DecodeGatherMateKey(6430598000)
check("GatherMate2 documented coord example", dx == 0.643 and dy == 0.598,
    tostring(dx) .. "," .. tostring(dy))

slash("import gathermate2")
check("import added three nodes", ADDON:NodeCount(1429) == 3, ADDON:NodeCount(1429))
local herbX, herbY, herbKind
for _, node in ipairs(ADDON:NodeListForMap(1429)) do
    if node.kind == "herb" and math.abs(node.y - 0.62) < 1e-9 then
        herbX, herbY, herbKind = node.x, node.y, node.kind
    end
end
check("import decoded coordinates", herbX == 0.5 and herbY == 0.62 and herbKind == "herb",
    tostring(herbX) .. "," .. tostring(herbY) .. "," .. tostring(herbKind))

slash("import gathermate2")
check("import is idempotent", ADDON:NodeCount(1429) == 3, ADDON:NodeCount(1429))

-- Baked seed merge at query time (a tiny stand-in for data.lua).
slash("clear yes")
ADDON:AddNode(1429, 0.5, 0.5, "herb") -- learned node, must survive
ADDON.SeedData = {
    version = "test-seed",
    icons = {
        [401] = "Interface\\AddOns\\NodeTaxi\\Media\\Herb\\peacebloom.tga",
        [201] = "Interface\\AddOns\\NodeTaxi\\Media\\Mine\\copper.tga",
    },
    herbs = { [1429] = { keys = { 5000500000, 5000620000 }, ids = { 401, 402 } } },
    mines = { [1429] = { keys = { 5200560000 }, ids = { 201 } } },
}
local merged = ADDON:NodeListForMap(1429)
check("seed merged into node list", #merged == 3, #merged)
check("seed did not touch saved nodes", ADDON:NodeCount(1429) == 1, ADDON:NodeCount(1429))
check("seed snapshot count", ADDON:SeedCount(nil) == 3, ADDON:SeedCount(nil))
check("specific icon selected", ADDON.NodeIcon({ kind = "herb", nodeID = 401 }) == ADDON.SeedData.icons[401])
check("generic icon fallback", type(ADDON.NodeIcon({ kind = "ore" })) == "string")

slash("near 50")
local nearHeader = false
for i = math.max(1, #messages - 12), #messages do
    if messages[i]:find("known node", 1, true) then nearHeader = true end
end
check("near lists known nodes", nearHeader)

slash("validate")
local validatePrinted = false
for i = math.max(1, #messages - 20), #messages do
    if messages[i]:find("validate", 1, true) then validatePrinted = true end
end
check("validate prints a result", validatePrinted)
check("log has persisted entries", #_G.NodeTaxiDB.log > 0, #_G.NodeTaxiDB.log)

slash("log 10")
local logHeader = false
for i = math.max(1, #messages - 30), #messages do
    if messages[i]:find("entries; last", 1, true) then logHeader = true end
end
check("log command prints entries", logHeader)

slash("log chat off")
check("log chat can be disabled", ADDON.settings.logChat == false)
slash("log chat on")
check("log chat can be re-enabled", ADDON.settings.logChat == true)

slash("kind ore")
local oreOnly = ADDON:NodeListForMap(1429)
check("kind filter applies to the seed", #oreOnly == 1 and oreOnly[1].kind == "ore", #oreOnly)
slash("kind both")

slash("seed")
check("seed command does not write nodes", ADDON:NodeCount(1429) == 1, ADDON:NodeCount(1429))

trackingTest = "ore"
slash("kind auto")
local oreFiltered = ADDON:NodeListForMap(1429)
local allOre = true
for _, node in ipairs(oreFiltered) do
    if node.kind == "herb" then allOre = false end
end
check("auto filter follows Find Minerals", allOre and #oreFiltered == 1, #oreFiltered)

trackingTest = "herb"
ADDON:OnTrackingChanged()
local herbFiltered = ADDON:NodeListForMap(1429)
local allHerb = true
for _, node in ipairs(herbFiltered) do
    if node.kind == "ore" then allHerb = false end
end
check("auto filter follows Find Herbs", allHerb and #herbFiltered == 2, #herbFiltered)

trackingTest = nil
slash("kind both")

-- Zone transitions use only real points: learned crossings and map links.
NodeTaxiDB.transitions = {}
ADDON.mapLinkCache = {}
C_Map.GetMapLinksForMap = nil

-- 1b. Baked Carbonite coordinate table.
local seedData = ADDON.TransitionData
check("baked transition table loaded", seedData and #seedData.connections == 63,
    seedData and #seedData.connections)

local function findSeed(a, b)
    for _, c in ipairs(seedData.connections) do
        if (c.a == a and c.b == b) or (c.a == b and c.b == a) then
            return c
        end
    end
end

local tirisfalSilverpine = findSeed(1420, 1421)
check("baked Tirisfal-Silverpine crossing exists", tirisfalSilverpine ~= nil)
if tirisfalSilverpine then
    local ax = tirisfalSilverpine.a == 1420 and tirisfalSilverpine.ax or tirisfalSilverpine.bx
    local ay = tirisfalSilverpine.a == 1420 and tirisfalSilverpine.ay or tirisfalSilverpine.by
    check("baked Tirisfal-Silverpine exact exit", ax == 54.14 and ay == 75.77, tostring(ax) .. "," .. tostring(ay))
end

local tirisfalWPL = findSeed(1420, 1422)
check("baked Tirisfal-WPL crossing exists", tirisfalWPL ~= nil)
local elwynnPath = ADDON:FindZoneRoute(1420, 1429, 0.567, 0.494)
check("baked route reaches Elwynn", elwynnPath and elwynnPath[#elwynnPath] == 1429)
check("baked route starts at Tirisfal", elwynnPath and elwynnPath[1] == 1420)

-- 2. Baked Carbonite points route immediately, before any learning.
NodeTaxiDB.transitions = {}
C_Map.GetMapLinksForMap = nil
ADDON.mapLinkCache = {}
playerZoneMap = 1420
playerZoneX, playerZoneY = 0.567, 0.494
-- A node in a later zone proves the display plan covers more than the current leg.
ADDON:AddNode(1421, 0.56, 0.40, "ore")
ADDON.state.dest = { map = 1429, x = 0.8, y = 0.5, title = "Baked transition test" }
local bakedBuilt = ADDON:BuildRoute(true)
check("baked crossing builds immediately", bakedBuilt == true)
local bakedRoute = ADDON.state.route
check("baked crossing source", bakedRoute and bakedRoute.cross
    and bakedRoute.cross.source == "seed")
check("baked crossing next map", bakedRoute and bakedRoute.cross.nextMap == 1421,
    bakedRoute and bakedRoute.cross and bakedRoute.cross.nextMap)
check("baked crossing uses real Tirisfal exit", bakedRoute and bakedRoute.dest.map == 1420
    and math.abs(bakedRoute.dest.x - 0.5414) < 1e-6
    and math.abs(bakedRoute.dest.y - 0.7577) < 1e-6)
check("baked crossing is not a huge geometric jump", bakedRoute and bakedRoute.plan.length < 2000,
    bakedRoute and bakedRoute.plan.length)
check("baked route has a leg for every zone", bakedRoute and bakedRoute.legs
    and #bakedRoute.legs >= 10, bakedRoute and bakedRoute.legs and #bakedRoute.legs)
check("baked route ends in Elwynn", bakedRoute and bakedRoute.legs
    and bakedRoute.legs[#bakedRoute.legs].map == 1429)
check("future leg nodes are included", bakedRoute and bakedRoute.totalNodes
    and bakedRoute.totalNodes > #bakedRoute.nodes, bakedRoute and bakedRoute.totalNodes)
local silverpineLeg = bakedRoute and bakedRoute.legs and bakedRoute.legs[2]
check("Silverpine leg carries its node", silverpineLeg and #silverpineLeg.nodes >= 1,
    silverpineLeg and #silverpineLeg.nodes)
check("corridor data loaded", ADDON.CorridorData and ADDON.CorridorData.zones
    and ADDON.CorridorData.zones[1421] ~= nil)
check("Silverpine leg has a corridor spine", silverpineLeg and silverpineLeg.corridorPoints
    and #silverpineLeg.corridorPoints >= 2,
    silverpineLeg and silverpineLeg.corridorPoints and #silverpineLeg.corridorPoints)
check("corridor reference is real points", silverpineLeg and silverpineLeg.corridorPoints
    and silverpineLeg.corridorPoints[1].x ~= nil and silverpineLeg.corridorPoints[1].y ~= nil)
check("visible path follows the corridor through nodes", silverpineLeg and silverpineLeg.routePoints
    and #silverpineLeg.routePoints > #silverpineLeg.nodes + 2,
    silverpineLeg and silverpineLeg.routePoints and #silverpineLeg.routePoints)
local routeTouchesNode = false
if silverpineLeg and silverpineLeg.routePoints and silverpineLeg.nodes[1] then
    for _, point in ipairs(silverpineLeg.routePoints) do
        if math.abs(point.x - silverpineLeg.nodes[1].x) < 1e-9
            and math.abs(point.y - silverpineLeg.nodes[1].y) < 1e-9 then
            routeTouchesNode = true
        end
    end
end
check("visible path detours through the node", routeTouchesNode)
check("every known leg node is exposed", silverpineLeg and silverpineLeg.allNodes
    and #silverpineLeg.allNodes >= #silverpineLeg.nodes,
    silverpineLeg and silverpineLeg.allNodes and #silverpineLeg.allNodes)

-- A tight cluster: each node is within 100 yd of the previous one, so the
-- branch walk must take all three before merging back to the corridor.
local clusterLeg = {
    map = 1421,
    startX = silverpineLeg.startX,
    startY = silverpineLeg.startY,
    destX = silverpineLeg.destX,
    destY = silverpineLeg.destY,
    corridorPoints = silverpineLeg.corridorPoints,
    corridorStart = silverpineLeg.corridorStart,
    corridorEnd = silverpineLeg.corridorEnd,
    allNodes = {
        { x = 0.56, y = 0.40, kind = "ore", nodeID = 201 },
        { x = 0.565, y = 0.405, kind = "ore", nodeID = 201 },
        { x = 0.555, y = 0.395, kind = "ore", nodeID = 201 },
        { x = 0.560, y = 0.300, kind = "ore", nodeID = 201 },
    },
}
ADDON:BuildCorridorLeg(clusterLeg)
check("branch takes the whole nearby cluster", #clusterLeg.nodes == 4, #clusterLeg.nodes)

-- A leg with no corridor (transport or uncovered zone) must still draw a
-- visible node line instead of going blank.
local fallbackLeg = {
    map = 1434,
    startX = 0.60, startY = 0.60,
    destX = 0.30, destY = 0.30,
    nodes = { { x = 0.50, y = 0.50, kind = "ore" } },
}
ADDON:BuildFallbackLeg(fallbackLeg)
check("no-corridor leg has a visible fallback line",
    fallbackLeg.routePoints and #fallbackLeg.routePoints == 3,
    fallbackLeg.routePoints and #fallbackLeg.routePoints)
check("all-node display defaults on", ADDON.settings.allNodes == true)
check("node deviation defaults to 100 yards", ADDON.settings.spur == 100,
    ADDON.settings.spur)
local corridorLegs = 0
for _, leg in ipairs(bakedRoute and bakedRoute.legs or {}) do
    if leg.corridorPoints then corridorLegs = corridorLegs + 1 end
end
check("several legs use corridor backbones", corridorLegs >= 5, corridorLegs)

-- 1. Learn a crossing from an actual zone change.
playerZoneMap = 1420
playerZoneX, playerZoneY = 0.49, 0.5
ADDON.lastPos = { map = 1420, x = 0.49, y = 0.5, t = GetTime() - 1, onTaxi = false }
playerZoneMap = 1429
playerZoneX, playerZoneY = 0.01, 0.5
ADDON:RecordZoneTransition()
local learned = NodeTaxiDB.transitions[1420] and NodeTaxiDB.transitions[1420][1429]
check("crossing is learned from a zone change", learned ~= nil)
check("learned crossing has a real exit", learned and learned.fromX == 0.49 and learned.fromY == 0.5)
check("learned crossing has a real entry", learned and learned.toX == 0.01 and learned.toY == 0.5)
check("reverse crossing is learned", NodeTaxiDB.transitions[1429] and NodeTaxiDB.transitions[1429][1420] ~= nil)

-- 3. Build a cross-zone leg using the learned point.
playerZoneMap = 1420
playerZoneX, playerZoneY = 0.2, 0.5
slash("crossings")
local crossingHeader = false
for i = math.max(1, #messages - 8), #messages do
    if messages[i]:find("known real crossings", 1, true) then crossingHeader = true end
end
check("crossings command lists learned edge", crossingHeader)
ADDON:AddNode(1420, 0.3, 0.5, "ore")
ADDON.state.dest = { map = 1429, x = 0.8, y = 0.5, title = "Cross-zone test" }
local crossBuilt = ADDON:BuildRoute(true)
check("cross-zone route builds", crossBuilt == true)
local crossRoute = ADDON.state.route
check("cross-zone leg recorded", crossRoute and crossRoute.cross ~= nil)
check("cross-zone next map", crossRoute and crossRoute.cross.nextMap == 1429,
    crossRoute and crossRoute.cross and tostring(crossRoute.cross.nextMap))
check("cross-zone uses learned source", crossRoute and crossRoute.cross.source == "learned")
check("cross-zone route ends at real exit",
    crossRoute and crossRoute.dest.map == 1420 and crossRoute.dest.x == 0.49)
check("cross-zone path continues to target", crossRoute and crossRoute.crossPath and #crossRoute.crossPath >= 3,
    crossRoute and crossRoute.crossPath and #crossRoute.crossPath)
check("cross-zone leg includes a node", crossRoute and #crossRoute.nodes >= 1)

-- 3. After crossing, the next leg is a normal same-zone leg.
playerZoneMap = 1429
playerZoneX, playerZoneY = 0.55, 0.5
ADDON.state.dest = { map = 1429, x = 0.2, y = 0.5, title = "Same-zone after crossing" }
local sameZoneBuilt = ADDON:BuildRoute(true)
check("next-zone leg builds", sameZoneBuilt == true)
check("next-zone leg is same-zone", ADDON.state.route and ADDON.state.route.cross == nil)
check("next-zone destination is local", ADDON.state.route and ADDON.state.route.dest.map == 1429)

-- 4. A client map link is also a real transition point.
NodeTaxiDB.transitions = {}
ADDON.mapLinkCache = {}
C_Map.GetMapLinksForMap = function(mapID)
    if mapID == 1420 then
        return { {
            linkedUiMapID = 1429,
            position = { GetXY = function() return 0.4, 0.5 end },
            name = "Test Link",
            atlasName = "test-atlas",
        } }
    end
    return {}
end
playerZoneMap = 1420
playerZoneX, playerZoneY = 0.2, 0.5
ADDON.state.dest = { map = 1429, x = 0.8, y = 0.5, title = "Link test" }
local linkBuilt = ADDON:BuildRoute(true)
check("map-link cross-zone builds", linkBuilt == true)
check("map-link source recorded", ADDON.state.route and ADDON.state.route.cross
    and ADDON.state.route.cross.source == "link")
check("map-link exit used", ADDON.state.route and ADDON.state.route.dest.x == 0.4)
check("map-link name recorded", ADDON.state.route and ADDON.state.route.cross
    and ADDON.state.route.cross.name == "Test Link")

-- 5. With no baked crossing, learned crossing, or link, refuse the leg.
NodeTaxiDB.transitions = {}
C_Map.GetMapLinksForMap = nil
ADDON.mapLinkCache = {}
playerZoneMap = 1420
playerZoneX, playerZoneY = 0.2, 0.5
ADDON.state.dest = { map = 2482, x = 0.8, y = 0.5, title = "No transition test" }
local noRouteBuilt = ADDON:BuildRoute(true)
check("unknown crossing yields no route", noRouteBuilt == false)
check("unknown crossing leaves no stale route", ADDON.state.route == nil)
local unknownMessage = messages[#messages] or ""
check("unknown crossing says so", unknownMessage:find("no known crossing", 1, true) ~= nil,
    unknownMessage)

playerZoneMap = 1429
playerZoneX, playerZoneY = 0.5, 0.5

-- All known nodes are visible even with no route and with the map unexplored.
local savedRoute = ADDON.state.route
ADDON.state.route = nil
WorldMapFrame.IsShown = function() return true end
WorldMapFrame.GetMapID = function() return 1419 end
C_Map.GetMapRectOnMap = function(child, parent)
    if parent == 1419 then
        return 0.0, 1.0, 0.0, 1.0
    end
    return nil
end
ADDON:RedrawWorld()
check("nodes visible without a route", ADDON:OverlayDebugInfo().markers > 0,
    ADDON:OverlayDebugInfo().markers)
ADDON.state.route = savedRoute

-- Save/load round trip of the settings table.
check("settings persisted in memory", _G.NodeTaxiDB.settings.corridor == 250)
check("TomTom was never modified", addWaypointCalls == 0)

check("produced chat output", #messages > 10, #messages)

print(string.format("%d checks, %d failure(s)", checks, failures))
if failures > 0 then
    os.exit(1)
end
