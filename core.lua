--[[--------------------------------------------------------------------------
    NodeTaxi - core
    --------------------------------------------------------------------------
    Reads the current TomTom arrow target (read-only: this addon never adds,
    removes or re-targets TomTom waypoints), learns resource nodes from your
    own gathering casts, plans a detour route through the nodes that lie
    between you and that target, and hands the result to overlay.lua.

    Slash: /nodetaxi or /nt
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local Route = ns.Route

local NodeTaxi = ns

local DEFAULTS = {
    corridor = 300,   -- yards either side of the straight line
    maxNodes = 8,     -- nodes a route may visit
    detour = 1.8,     -- route length / direct distance
    arrive = 18,      -- yards at which a node counts as collected
    auto = true,      -- rebuild when the TomTom arrow target changes
    kind = "auto",    -- "auto" follows the active tracking, else herb/ore/both
    replan = 30,      -- yards moved before the remaining route is re-ordered (0 = off)
    ring = 100,       -- yards at which a node marker becomes a hollow ring (0 = off)
    log = true,       -- keep a persistent diagnostic log in NodeTaxiDB
    logChat = true,   -- also print one line per gather/validation
    debug = false,
    welcome = true,
    allNodes = true,  -- draw every known node under the displayed map
    spur = 100,      -- max yards a selected node may pull away from the reference
    cluster = 4,     -- max nodes selected from one nearby cluster
}

NodeTaxi.nodeRevision = NodeTaxi.nodeRevision or 0

NodeTaxi.state = NodeTaxi.state or {
    dest = nil,
    route = nil,
    index = 1,
}

local state = NodeTaxi.state
local settings
local db

local lastCapture = -100
local buildToken = 0
local watchCasts = false
local herbNames, oreNames = {}, {}

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99NodeTaxi|r: " .. tostring(message))
    end
end
NodeTaxi.Print = Print

local function MapName(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end
NodeTaxi.MapName = MapName

local function CoordText(x, y)
    return string.format("%.1f, %.1f", (x or 0) * 100, (y or 0) * 100)
end
NodeTaxi.CoordText = CoordText

local function AddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(ADDON_NAME, "Version") or "?"
    end
    return "?"
end

local function GetHBD()
    if NodeTaxi.hbd == nil then
        local ok, lib = pcall(function()
            if LibStub then
                return LibStub("HereBeDragons-2.0", true)
            end
        end)
        NodeTaxi.hbd = (ok and lib) or false
    end
    return NodeTaxi.hbd or nil
end
NodeTaxi.GetHBD = GetHBD

local function GetPlayerPos(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then
        return nil
    end

    local ok, pos, posY = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then
        return nil
    end

    -- Modern clients return a vector; keep the two-number form as a fallback.
    if type(pos) == "table" then
        if pos.GetXY then
            local x, y = pos:GetXY()
            if x and y then
                return x, y
            end
        end
        if pos.x and pos.y then
            return pos.x, pos.y
        end
    elseif type(pos) == "number" and type(posY) == "number" then
        return pos, posY
    end

    return nil
end
NodeTaxi.GetPlayerPos = GetPlayerPos

-- Prefer HereBeDragons' zone position (it resolves caves/sub-zones to the
-- outdoor zone and agrees with the coordinates we use for nodes), then fall
-- back to the raw C_Map position.
function NodeTaxi:GetPlayerZone()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local hbd = GetHBD()

    if hbd and hbd.GetPlayerZonePosition then
        local ok, x, y, hmap = pcall(hbd.GetPlayerZonePosition, hbd)
        if ok and x and y and x > 0 and y > 0 and hmap and (not mapID or hmap == mapID) then
            return hmap, x, y
        end
    end

    if mapID then
        local x, y = GetPlayerPos(mapID)
        if x and y then
            return mapID, x, y
        end
    end

    return nil
end

function NodeTaxi:GetZoneSize(mapID)
    local hbd = GetHBD()
    if hbd and hbd.GetZoneSize then
        local ok, width, height = pcall(hbd.GetZoneSize, hbd, mapID)
        if ok and width and height and width > 0 and height > 0 then
            return width, height
        end
    end
    return nil
end

function NodeTaxi:DistanceOnMap(mapID, ax, ay, bx, by)
    local width, height = self:GetZoneSize(mapID)
    if not width then
        return nil
    end
    local dx, dy = (ax - bx) * width, (ay - by) * height
    return math.sqrt(dx * dx + dy * dy)
end

local NODE_MERGE_YARDS = 12
local GATHERMATE_MERGE_YARDS = 12
local SEED_MATCH_YARDS = 60
local LOG_LIMIT = 300

--[[ Tracking filter ---------------------------------------------------------
    The user sees only the node type their minimap tracking shows. The client
    exposes the tracking list through C_Minimap.GetTrackingInfo(); the names
    for Find Herbs (2383) and Find Minerals (2580) are compared, with spellID
    as an extra check when the client provides it.
----------------------------------------------------------------------------]]
local TRACKING_HERB = 2383
local TRACKING_ORE = 2580

local function TrackingSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture then
            return texture
        end
    end
    if GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, spellID)
        if ok and texture then
            return texture
        end
    end
    return nil
end

local function TrackingSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then
            return name
        end
    end
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    return nil
end

function NodeTaxi:DetectTracking()
    local herbName = TrackingSpellName(TRACKING_HERB)
    local oreName = TrackingSpellName(TRACKING_ORE)
    local herbTexture = TrackingSpellTexture(TRACKING_HERB)
    local oreTexture = TrackingSpellTexture(TRACKING_ORE)
    local hasHerb, hasOre = false, false

    local function scan(info)
        if type(info) ~= "table" or not info.active then
            return
        end
        if info.spellID == TRACKING_HERB
            or (herbName and info.name == herbName)
            or (herbTexture and info.texture == herbTexture) then
            hasHerb = true
        elseif info.spellID == TRACKING_ORE
            or (oreName and info.name == oreName)
            or (oreTexture and info.texture == oreTexture) then
            hasOre = true
        end
    end

    local count
    if C_Minimap and C_Minimap.GetNumTrackingTypes then
        count = C_Minimap.GetNumTrackingTypes()
    elseif GetNumTrackingTypes then
        count = GetNumTrackingTypes()
    end

    for i = 1, count or 0 do
        local info
        if C_Minimap and C_Minimap.GetTrackingInfo then
            info = C_Minimap.GetTrackingInfo(i)
        elseif GetTrackingInfo then
            local name, texture, active = GetTrackingInfo(i)
            info = { name = name, texture = texture, active = active }
        end
        scan(info)
    end

    if hasHerb and hasOre then
        return "both"
    elseif hasHerb then
        return "herb"
    elseif hasOre then
        return "ore"
    end
    return nil
end

function NodeTaxi:GetEffectiveKind()
    if settings and settings.kind ~= "auto" then
        return settings.kind
    end

    local detected = self:DetectTracking()
    if detected then
        self.activeTracking = detected
    end
    return detected or self.activeTracking or "both"
end

function NodeTaxi:OnTrackingChanged()
    local detected = self:DetectTracking()
    if not detected then
        return
    end

    local previous = self.activeTracking
    self.activeTracking = detected
    if settings.kind == "auto" and detected ~= previous and state.route then
        self:BuildRoute(false)
    end
end

local function InitDB()
    NodeTaxiDB = NodeTaxiDB or {}
    db = NodeTaxiDB
    local oldVersion = db.version or 1
    db.version = 4

    db.settings = db.settings or {}
    for key, value in pairs(DEFAULTS) do
        if db.settings[key] == nil then
            db.settings[key] = value
        end
    end

    -- "both" was the old default. Existing installs should follow the
    -- player's active tracking now; an explicit herb/ore choice is kept.
    if oldVersion < 2 and db.settings.kind == "both" then
        db.settings.kind = "auto"
    end

    -- 0.9.8-0.9.11 shipped a 75-yard spur default. The minimap only renders
    -- around 80-100 yards, so use the full 100-yard band by default.
    if oldVersion < 4 and db.settings.spur == 75 then
        db.settings.spur = 100
    end

    db.nodes = db.nodes or {}
    db.transitions = db.transitions or {}
    db.log = db.log or {}
    while #db.log > LOG_LIMIT do
        table.remove(db.log, 1)
    end
    db.learnedSpells = db.learnedSpells or { herb = {}, ore = {} }
    db.learnedSpells.herb = db.learnedSpells.herb or {}
    db.learnedSpells.ore = db.learnedSpells.ore or {}
    settings = db.settings
    NodeTaxi.db = db
    NodeTaxi.settings = settings
    NodeTaxi.mapLinkCache = {}
end

local function InitSettingsIfNeeded()
    if not settings then
        InitDB()
    end
end

--[[ Diagnostic log ----------------------------------------------------------
    Persisted in NodeTaxiDB.log (last 300 events) so a gather/validation can be
    inspected after /reload even if the chat line was missed. Every gather
    records the distance to the closest baked node of the same kind, which is
    what tells us whether the snapshot actually matches the live node.
----------------------------------------------------------------------------]]
local function FormatDistance(value)
    if type(value) ~= "number" then
        return "none"
    end
    return string.format("%.0f", value)
end

local function AddLog(event, data)
    if not (db and db.log and settings and settings.log) then
        return
    end

    local entry = { t = time(), e = event }
    for key, value in pairs(data or {}) do
        entry[key] = value
    end

    local log = db.log
    log[#log + 1] = entry
    while #log > LOG_LIMIT do
        table.remove(log, 1)
    end
end
NodeTaxi.Log = AddLog

local function FormatLogEntry(entry)
    local clock = (entry.t and date) and date("%H:%M:%S", entry.t) or "?"
    local event = entry.e or "?"

    if event == "gather" then
        return string.format("%s gather %s %s %s seed=%s stored=%s dup=%s spell=%s(%s)",
            clock, tostring(entry.kind), CoordText(entry.x, entry.y), tostring(entry.verdict),
            FormatDistance(entry.seed), FormatDistance(entry.stored), tostring(entry.dup),
            tostring(entry.spell), tostring(entry.id))
    elseif event == "manual" then
        return string.format("%s manual %s %s seed=%s",
            clock, tostring(entry.kind), CoordText(entry.x, entry.y), FormatDistance(entry.seed))
    elseif event == "validate" then
        return string.format("%s validate herb=%s ore=%s stored=%s at %s",
            clock, FormatDistance(entry.herb), FormatDistance(entry.ore),
            FormatDistance(entry.stored), CoordText(entry.x, entry.y))
    elseif event == "crossing" then
        return string.format("%s crossing %s %s -> %s %s (%.0f yd)",
            clock, tostring(entry.from), CoordText(entry.fromX, entry.fromY),
            tostring(entry.to), CoordText(entry.toX, entry.toY), entry.distance or 0)
    elseif event == "route" then
        return string.format("%s route %d node(s) len=%.0f direct=%.0f target=%s cross=%s%s",
            clock, entry.nodes or 0, entry.len or 0, entry.direct or 0,
            CoordText(entry.tx, entry.ty), tostring(entry.cross or 0),
            entry.source and (" " .. tostring(entry.source)) or "")
    elseif event == "session" then
        return string.format("%s session v%s build=%s seed=%s (%s nodes)",
            clock, tostring(entry.v), tostring(entry.build), tostring(entry.seed),
            tostring(entry.seedNodes))
    end

    return clock .. " " .. event
end
NodeTaxi.FormatLogEntry = FormatLogEntry

--[[ Node storage -----------------------------------------------------------
    db.nodes[uiMapID] = {
        { x = 0..1, y = 0..1, kind = "herb"|"ore"|"manual", count = n, last = time },
        ...
    }
    Nodes are account wide. A gathering cast lands within a few yards of the
    node, so anything within NODE_MERGE_YARDS is treated as the same node.
----------------------------------------------------------------------------]]

-- GatherMate2 / baked-snapshot coordinate key:
--   round(x*10000) * 1000000 + round(y*10000) * 100
-- returns normalised x, y (0..1) or nil for a bad key.
local function DecodeGatherMateKey(key)
    local numeric = tonumber(key)
    if not numeric then
        return nil
    end

    local x = math.floor(numeric / 1000000) / 10000
    local y = math.floor((numeric % 1000000) / 100) / 10000
    if x < 0 or x > 1 or y < 0 or y > 1 then
        return nil
    end

    return x, y
end
NodeTaxi.DecodeGatherMateKey = DecodeGatherMateKey

-- GatherMate2 / baked-snapshot coordinate key:
--   round(x*10000) * 1000000 + round(y*10000) * 100
-- returns normalised x, y (0..1) or nil for a bad key.
function NodeTaxi:AddNode(mapID, x, y, kind, quiet)
    InitSettingsIfNeeded()
    if not (mapID and x and y) then
        return nil, false
    end
    NodeTaxi.nodeRevision = (NodeTaxi.nodeRevision or 0) + 1

    local list = db.nodes[mapID]
    if not list then
        list = {}
        db.nodes[mapID] = list
    end

    local width, height = self:GetZoneSize(mapID)
    for _, node in ipairs(list) do
        local distance
        if width then
            local dx, dy = (node.x - x) * width, (node.y - y) * height
            distance = math.sqrt(dx * dx + dy * dy)
        else
            local dx, dy = node.x - x, node.y - y
            distance = math.sqrt(dx * dx + dy * dy) * 1000
        end

        if distance <= NODE_MERGE_YARDS and node.kind == kind then
            node.count = (node.count or 1) + 1
            node.last = time()
            return node, true
        end
    end

    local node = {
        x = x,
        y = y,
        kind = kind or "manual",
        count = 1,
        last = time(),
    }
    list[#list + 1] = node

    if settings.debug and not quiet then
        Print(string.format("learned a %s node at %s (%s)", node.kind, CoordText(x, y), MapName(mapID) or mapID))
    end

    return node, false
end

function NodeTaxi:NodeCount(mapID)
    InitSettingsIfNeeded()
    if mapID then
        return #(db.nodes[mapID] or {})
    end

    local total = 0
    for _, list in pairs(db.nodes) do
        total = total + #list
    end
    return total
end

function NodeTaxi:NodeListForMap(mapID)
    InitSettingsIfNeeded()

    local filter = self:GetEffectiveKind()
    local function include(kind)
        return filter == "both"
            or kind == filter
            or (kind ~= "herb" and kind ~= "ore")
    end

    local result = {}
    for _, node in ipairs(db.nodes[mapID] or {}) do
        if include(node.kind) then
            result[#result + 1] = {
                map = mapID,
                x = node.x,
                y = node.y,
                kind = node.kind,
                count = node.count,
                last = node.last,
                nodeID = node.nodeID,
                src = node.src,
                coarse = node.coarse,
            }
        end
    end

    -- Merge the baked snapshot at query time. Copying 23k node tables into
    -- NodeTaxiDB would bloat SavedVariables; only the current zone is decoded.
    local seed = self.SeedData
    local width, height = self:GetZoneSize(mapID)
    if not (seed and width and height) then
        return result
    end

    local grid = {}
    local coarse = {}

    local function coarseCellKey(x, y)
        return math.floor(x * width / SEED_MATCH_YARDS) .. ":"
            .. math.floor(y * height / SEED_MATCH_YARDS)
    end

    local function coarseAdd(x, y, kind)
        local key = coarseCellKey(x, y)
        local bucket = coarse[key]
        if not bucket then
            bucket = {}
            coarse[key] = bucket
        end
        bucket[#bucket + 1] = { x = x, y = y, kind = kind }
    end

    local function coarseNear(x, y, kind)
        local cx = math.floor(x * width / SEED_MATCH_YARDS)
        local cy = math.floor(y * height / SEED_MATCH_YARDS)

        for ox = -1, 1 do
            for oy = -1, 1 do
                local bucket = coarse[(cx + ox) .. ":" .. (cy + oy)]
                if bucket then
                    for i = 1, #bucket do
                        local other = bucket[i]
                        if other.kind == kind then
                            local dx = (other.x - x) * width
                            local dy = (other.y - y) * height
                            if dx * dx + dy * dy <= SEED_MATCH_YARDS * SEED_MATCH_YARDS then
                                return true
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    local function cellKey(x, y)
        return math.floor(x * width / GATHERMATE_MERGE_YARDS) .. ":"
            .. math.floor(y * height / GATHERMATE_MERGE_YARDS)
    end

    local function addPoint(x, y, kind)
        local key = cellKey(x, y)
        local bucket = grid[key]
        if not bucket then
            bucket = {}
            grid[key] = bucket
        end
        bucket[#bucket + 1] = { x = x, y = y, kind = kind }
    end

    local function nearPoint(x, y, kind)
        local cx = math.floor(x * width / GATHERMATE_MERGE_YARDS)
        local cy = math.floor(y * height / GATHERMATE_MERGE_YARDS)

        for ox = -1, 1 do
            for oy = -1, 1 do
                local bucket = grid[(cx + ox) .. ":" .. (cy + oy)]
                if bucket then
                    for i = 1, #bucket do
                        local other = bucket[i]
                        if other.kind == kind then
                            local dx = (other.x - x) * width
                            local dy = (other.y - y) * height
                            if dx * dx + dy * dy <= GATHERMATE_MERGE_YARDS * GATHERMATE_MERGE_YARDS then
                                return true
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    for i = 1, #result do
        addPoint(result[i].x, result[i].y, result[i].kind)
        coarseAdd(result[i].x, result[i].y, result[i].kind)
    end

    local function mergeSeed(kind, zones)
        local entry = zones and zones[mapID]
        local keys = entry and entry.keys
        local ids = entry and entry.ids
        if not keys or not include(kind) then
            return
        end

        for i = 1, #keys do
            local x, y = DecodeGatherMateKey(keys[i])
            if x and not nearPoint(x, y, kind) and not coarseNear(x, y, kind) then
                result[#result + 1] = {
                    map = mapID,
                    x = x,
                    y = y,
                    kind = kind,
                    nodeID = ids and ids[i],
                    src = "seed",
                    coarse = true,
                }
                addPoint(x, y, kind)
            end
        end
    end

    mergeSeed("herb", seed.herbs)
    mergeSeed("ore", seed.mines)

    return result
end

function NodeTaxi:SeedCount(mapID)
    local seed = self.SeedData
    if not seed then
        return 0
    end

    if mapID then
        local herbs = seed.herbs and seed.herbs[mapID]
        local mines = seed.mines and seed.mines[mapID]
        return #((herbs and herbs.keys) or {}) + #((mines and mines.keys) or {})
    end

    local total = 0
    for _, entry in pairs(seed.herbs or {}) do total = total + #(entry.keys or {}) end
    for _, entry in pairs(seed.mines or {}) do total = total + #(entry.keys or {}) end
    return total
end

-- Closest baked node of one kind, in yards. Used by the gather log and by
-- the validation command to answer "does this live node match the snapshot?".
function NodeTaxi:NearestSeed(mapID, x, y, kind)
    local seed = self.SeedData
    if not seed then
        return nil
    end

    local zones = (kind == "ore") and seed.mines or seed.herbs
    local entry = zones and zones[mapID]
    local keys = entry and entry.keys
    local ids = entry and entry.ids
    local width, height = self:GetZoneSize(mapID)
    if not (keys and width) then
        return nil
    end

    local bestDistance, bestX, bestY, bestID
    for i = 1, #keys do
        local sx, sy = DecodeGatherMateKey(keys[i])
        if sx then
            local dx, dy = (sx - x) * width, (sy - y) * height
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                bestDistance, bestX, bestY = distance, sx, sy
                bestID = ids and ids[i]
            end
        end
    end

    if bestDistance then
        return math.sqrt(bestDistance), bestX, bestY, bestID
    end
    return nil
end

function NodeTaxi:NearestStored(mapID, x, y, kind)
    local width, height = self:GetZoneSize(mapID)
    if not width then
        return nil
    end

    local bestDistance, bestNode
    for _, node in ipairs(db.nodes[mapID] or {}) do
        if not kind or node.kind == kind then
            local dx, dy = (node.x - x) * width, (node.y - y) * height
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                bestDistance, bestNode = distance, node
            end
        end
    end

    if bestDistance then
        return math.sqrt(bestDistance), bestNode
    end
    return nil
end

--[[ GatherMate2 import ------------------------------------------------------
    GatherMate2 stores node positions in saved variables:
        GatherMate2HerbDB[uiMapID][coordKey] = nodeID
        GatherMate2MineDB[uiMapID][coordKey] = nodeID
    coordKey = round(x*10000) * 1000000 + round(y*10000) * 100
    (see GatherMate2:EncodeLoc / DecodeLoc).

    Importing from the user's own installed copy keeps the data local:
    NodeTaxi does not bundle or redistribute it. The user imports the data
    package into GatherMate2 first (/gathermate -> Import).
----------------------------------------------------------------------------]]
local function GetGatherMateSources()
    local sources = {}

    local function add(name, kind)
        local data = _G[name]
        if type(data) == "table" and next(data) then
            sources[#sources + 1] = { data = data, kind = kind, name = name }
        end
    end

    -- Only the GatherMate2 databases, i.e. after the user imported a data
    -- package there. The raw data-addon tables can contain retail-only maps
    -- and would pollute the route database on this client.
    add("GatherMate2HerbDB", "herb")
    add("GatherMate2MineDB", "ore")

    return sources
end
NodeTaxi.GetGatherMateSources = GetGatherMateSources

-- A cheap spatial index for a zone: keeps imports linear and makes a second
-- import idempotent (anything within 12 yards of a node of the same kind is
-- treated as the same node).
local function NewMergeGrid(mapID)
    local width, height = NodeTaxi:GetZoneSize(mapID)
    if not width or not height then
        return nil
    end

    local list = db.nodes[mapID]
    if not list then
        list = {}
        db.nodes[mapID] = list
    end

    local grid = {}
    local coarse = {}

    local function coarseCellKey(x, y)
        return math.floor(x * width / SEED_MATCH_YARDS) .. ":"
            .. math.floor(y * height / SEED_MATCH_YARDS)
    end

    local function coarseAdd(x, y, kind)
        local key = coarseCellKey(x, y)
        local bucket = coarse[key]
        if not bucket then
            bucket = {}
            coarse[key] = bucket
        end
        bucket[#bucket + 1] = { x = x, y = y, kind = kind }
    end

    local function coarseNear(x, y, kind)
        local cx = math.floor(x * width / SEED_MATCH_YARDS)
        local cy = math.floor(y * height / SEED_MATCH_YARDS)

        for ox = -1, 1 do
            for oy = -1, 1 do
                local bucket = coarse[(cx + ox) .. ":" .. (cy + oy)]
                if bucket then
                    for i = 1, #bucket do
                        local other = bucket[i]
                        if other.kind == kind then
                            local dx = (other.x - x) * width
                            local dy = (other.y - y) * height
                            if dx * dx + dy * dy <= SEED_MATCH_YARDS * SEED_MATCH_YARDS then
                                return true
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    local function cellKey(x, y)
        return math.floor(x * width / GATHERMATE_MERGE_YARDS) .. ":"
            .. math.floor(y * height / GATHERMATE_MERGE_YARDS)
    end

    local function index(node)
        local key = cellKey(node.x, node.y)
        local bucket = grid[key]
        if not bucket then
            bucket = {}
            grid[key] = bucket
        end
        bucket[#bucket + 1] = node
    end

    local function add(node)
        list[#list + 1] = node
        index(node)
    end

    for i = 1, #list do
        index(list[i])
    end

    local function near(x, y, kind)
        local cx = math.floor(x * width / GATHERMATE_MERGE_YARDS)
        local cy = math.floor(y * height / GATHERMATE_MERGE_YARDS)

        for ox = -1, 1 do
            for oy = -1, 1 do
                local bucket = grid[(cx + ox) .. ":" .. (cy + oy)]
                if bucket then
                    for i = 1, #bucket do
                        local node = bucket[i]
                        if node.kind == kind then
                            local dx = (node.x - x) * width
                            local dy = (node.y - y) * height
                            if dx * dx + dy * dy <= GATHERMATE_MERGE_YARDS * GATHERMATE_MERGE_YARDS then
                                return true
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    return { list = list, add = add, near = near }
end

function NodeTaxi:ImportGatherMate2()
    InitSettingsIfNeeded()

    local sources = GetGatherMateSources()
    if #sources == 0 then
        Print("no GatherMate2 data found.")
        Print("install GatherMate2 (Forever build) plus a GatherMate2 data package, import it in /gathermate -> Import, then run /nt import gathermate2.")
        return
    end

    local imported, skipped, invalid = 0, 0, 0
    local grids, touchedZones = {}, {}

    for _, source in ipairs(sources) do
        for zone, coords in pairs(source.data) do
            zone = tonumber(zone)
            if zone and type(coords) == "table" then
                local grid = grids[zone]
                if grid == nil then
                    grid = NewMergeGrid(zone) or false
                    grids[zone] = grid
                end

                if grid then
                    for key, nodeID in pairs(coords) do
                        local x, y = DecodeGatherMateKey(key)
                        if x then
                            if grid.near(x, y, source.kind) then
                                skipped = skipped + 1
                            else
                                grid.add({
                                    x = x,
                                    y = y,
                                    kind = source.kind,
                                    nodeID = tonumber(nodeID),
                                    count = 1,
                                    last = time(),
                                    src = "gathermate2",
                                    coarse = true,
                                })
                                imported = imported + 1
                                touchedZones[zone] = true
                            end
                        else
                            invalid = invalid + 1
                        end
                    end
                end
            end
        end
    end

    local zoneCount = 0
    for _ in pairs(touchedZones) do
        zoneCount = zoneCount + 1
    end

    Print(string.format("GatherMate2 import: %d new node(s), %d duplicate(s), %d bad key(s), %d zone(s) touched.",
        imported, skipped, invalid, zoneCount))

    if imported == 0 then
        Print("nothing new. Make sure the data was imported into GatherMate2 first (/gathermate -> Import).")
        return
    end

    if state.route then
        self:BuildRoute(false)
    end
end

--[[ TomTom integration (read only) -----------------------------------------
    TomTom fires "ArrowTargetChanged" with the active arrow waypoint (or nil).
    The initial target is read once through TomTom's private getter, because
    a target can already be active when this addon loads. Nothing here calls
    AddWaypoint, RemoveWaypoint or SetCrazyArrow.
----------------------------------------------------------------------------]]
local function ReadArrowTarget()
    local tomtom = _G.TomTom
    if not tomtom then
        return nil
    end

    local private = tomtom.private
    if private and type(private.GetCrazyArrowTarget) == "function" then
        local ok, uid = pcall(private.GetCrazyArrowTarget)
        if ok and type(uid) == "table" then
            return uid
        end
    end

    return nil
end
NodeTaxi.ReadArrowTarget = ReadArrowTarget

local function DestFromUid(uid)
    if type(uid) ~= "table" then
        return nil
    end

    local mapID, x, y = uid[1], uid[2], uid[3]
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end

    return {
        map = mapID,
        x = x,
        y = y,
        title = uid.title,
        from = uid.from,
    }
end

local function SameDest(a, b)
    if not a or not b then
        return a == b
    end
    return a.map == b.map
        and math.abs(a.x - b.x) < 0.0001
        and math.abs(a.y - b.y) < 0.0001
end

function NodeTaxi:GetDestination()
    return state.dest
end

function NodeTaxi:ClearRoute(reason, quiet)
    local hadRoute = state.route ~= nil
    state.route = nil
    state.index = 1

    if NodeTaxi.ClearWorldOverlay then
        NodeTaxi:ClearWorldOverlay()
    end
    if NodeTaxi.ClearMinimapOverlay then
        NodeTaxi:ClearMinimapOverlay()
    end

    if hadRoute and reason and not quiet then
        Print(reason)
    end
end

function NodeTaxi:Redraw()
    if NodeTaxi.RedrawWorld then
        NodeTaxi:RedrawWorld()
    end
    if NodeTaxi.RedrawMinimap then
        NodeTaxi:RedrawMinimap()
    end
end

--[[ Real zone transitions -------------------------------------------------
    A crossing is only used if its point is real:
      * learned from an actual player zone change (both sides recorded), or
      * a client map link (C_Map.GetMapLinksForMap) whose pin points at
        another zone.
    There is deliberately no geometric border/rectangle fallback. A map edge
    is not a pass, and sending someone at a mountain is worse than not routing.
----------------------------------------------------------------------------]]
local function GetMapInfoRaw(mapID)
    if not (C_Map and C_Map.GetMapInfo) then
        return nil
    end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok then
        return info
    end
    return nil
end

-- Bake Carbonite's paired zone-connection coordinates. A target can have
-- more than one crossing (for example two Dun Morogh passes); keep all of
-- them and choose the one nearest the player when building the leg.
NodeTaxi.seedEdges = {}
do
    local function AddSeedEdge(fromMap, toMap, fromX, fromY, toX, toY, kind, label)
        local byTarget = NodeTaxi.seedEdges[fromMap]
        if not byTarget then
            byTarget = {}
            NodeTaxi.seedEdges[fromMap] = byTarget
        end
        local list = byTarget[toMap]
        if not list then
            list = {}
            byTarget[toMap] = list
        end
        -- Carbonite stores zone-map percentages (0..100); the planner uses
        -- normalised 0..1 coordinates like every other map API.
        list[#list + 1] = {
            fromX = fromX / 100,
            fromY = fromY / 100,
            toX = toX / 100,
            toY = toY / 100,
            kind = kind or "link",
            name = label,
            source = "seed",
        }
    end

    local data = ns.TransitionData
    if data and data.connections then
        for _, connection in ipairs(data.connections) do
            AddSeedEdge(connection.a, connection.b, connection.ax, connection.ay,
                connection.bx, connection.by, connection.kind, connection.name)
            AddSeedEdge(connection.b, connection.a, connection.bx, connection.by,
                connection.ax, connection.ay, connection.kind, connection.name)
        end
    end
end

local function ChooseSeedEdge(list, x, y)
    if not x or #list == 1 then
        return list[1]
    end
    local best, bestDistance = list[1], math.huge
    for i = 1, #list do
        local edge = list[i]
        local dx, dy = edge.fromX - x, edge.fromY - y
        local distance = dx * dx + dy * dy
        if distance < bestDistance then
            best, bestDistance = edge, distance
        end
    end
    return best
end

function NodeTaxi:GetTransitionEdges(mapID, x, y)
    local edges = {}

    -- Baked real coordinates first; if there are several crossings to the
    -- same zone, use the one nearest the player.
    local seeded = self.seedEdges[mapID]
    if seeded then
        for target, list in pairs(seeded) do
            edges[target] = ChooseSeedEdge(list, x, y)
        end
    end

    -- Client map-link pins fill gaps that the baked data does not cover.
    local links = self:GetMapLinkEdges(mapID)
    if links then
        for target, edge in pairs(links) do
            if not edges[target] then
                edges[target] = edge
            end
        end
    end

    -- A learned crossing is authoritative and overrides both.
    local learned = db.transitions[mapID]
    if learned then
        for target, edge in pairs(learned) do
            edges[target] = edge
        end
    end

    return edges
end

function NodeTaxi:GetMapLinkEdges(mapID)
    self.mapLinkCache = self.mapLinkCache or {}
    local cached = self.mapLinkCache[mapID]
    if cached ~= nil then
        return cached or nil
    end

    local edges = {}
    if C_Map and C_Map.GetMapLinksForMap then
        local ok, links = pcall(C_Map.GetMapLinksForMap, mapID)
        if ok and type(links) == "table" then
            for _, link in ipairs(links) do
                local target = link.linkedUiMapID
                local position = link.position
                local x, y
                if position and position.GetXY then
                    x, y = position:GetXY()
                end

                if target and target ~= mapID and x then
                    local info = GetMapInfoRaw(target)
                    if info and info.mapType == 3 then
                        edges[target] = {
                            fromX = x,
                            fromY = y,
                            source = "link",
                            name = link.name,
                            atlas = link.atlasName,
                        }
                    end
                end
            end
        end
    end

    self.mapLinkCache[mapID] = edges
    return edges
end

function NodeTaxi:FindZoneRoute(startMap, destMap, startX, startY)
    if startMap == destMap then
        return { startMap }
    end

    local distance = { [startMap] = 0 }
    local pathTo = { [startMap] = { startMap } }
    local open = { startMap }
    local inOpen = { [startMap] = true }

    while #open > 0 do
        local bestIndex, bestMap, bestDistance = 1, open[1], distance[open[1]]
        for i = 2, #open do
            local candidate = open[i]
            if distance[candidate] < bestDistance then
                bestIndex, bestMap, bestDistance = i, candidate, distance[candidate]
            end
        end
        table.remove(open, bestIndex)
        inOpen[bestMap] = nil

        if bestMap == destMap then
            return pathTo[bestMap]
        end

        local edges = self:GetTransitionEdges(bestMap,
            bestMap == startMap and startX or nil,
            bestMap == startMap and startY or nil)
        for target, edge in pairs(edges) do
            -- Prefer walking. Boats, zeppelins, portals and the tram are
            -- allowed, but only when they are genuinely the better route
            -- (normally a cross-continent trip).
            local cost = (edge.kind == "land" or edge.source == "learned") and 1 or 10
            local candidate = distance[bestMap] + cost
            if not distance[target] or candidate < distance[target] then
                distance[target] = candidate
                local path = {}
                for i = 1, #pathTo[bestMap] do
                    path[i] = pathTo[bestMap][i]
                end
                path[#path + 1] = target
                pathTo[target] = path
                if not inOpen[target] then
                    open[#open + 1] = target
                    inOpen[target] = true
                end
            end
        end
    end

    return nil
end

function NodeTaxi:BuildCrossPath(zoneRoute, playerMap, px, py, dest)
    local path = { { map = playerMap, x = px, y = py } }

    for i = 2, #zoneRoute do
        local from, to = zoneRoute[i - 1], zoneRoute[i]
        local edge = self:GetTransitionEdges(from, from == playerMap and px or nil,
            from == playerMap and py or nil)[to]
        if edge and edge.fromX then
            path[#path + 1] = {
                map = from,
                x = edge.fromX,
                y = edge.fromY,
                transition = true,
                source = edge.source,
                name = edge.name,
            }
            if edge.toX then
                path[#path + 1] = {
                    map = to,
                    x = edge.toX,
                    y = edge.toY,
                    transition = true,
                    source = edge.source,
                }
            end
        end
    end

    path[#path + 1] = { map = dest.map, x = dest.x, y = dest.y }
    return path
end

-- Record a crossing when the player actually changes zone. The last sampled
-- position is on the old side and the current position on the new side, so
-- both ends of the edge are real walkable positions.
function NodeTaxi:RecordZoneTransition()
    if not db then
        return
    end

    local map, x, y = self:GetPlayerZone()
    if not (map and x and y) then
        return
    end

    local previous = self.lastPos
    self.lastPos = {
        map = map,
        x = x,
        y = y,
        t = GetTime(),
        onTaxi = UnitOnTaxi and UnitOnTaxi("player") or false,
    }

    if not previous or previous.map == map or previous.onTaxi then
        return
    end

    local elapsed = GetTime() - (previous.t or 0)
    if elapsed < 0 or elapsed > 10 then
        return
    end

    local fromInfo = GetMapInfoRaw(previous.map)
    local toInfo = GetMapInfoRaw(map)
    if not (fromInfo and toInfo and fromInfo.mapType == 3 and toInfo.mapType == 3) then
        return
    end

    -- Skip hearth/teleport/flight jumps; a real border crossing is close.
    local hbd = GetHBD()
    local distance
    if hbd and hbd.GetZoneDistance then
        local ok, value = pcall(hbd.GetZoneDistance, hbd, previous.map, previous.x, previous.y, map, x, y)
        if ok then
            distance = value
        end
    end
    if distance and distance > 300 then
        return
    end

    local fromTable = db.transitions[previous.map] or {}
    db.transitions[previous.map] = fromTable
    local edge = fromTable[map] or { count = 0 }
    edge.fromX, edge.fromY = previous.x, previous.y
    edge.toX, edge.toY = x, y
    edge.count = (edge.count or 0) + 1
    edge.last = time()
    edge.source = "learned"
    fromTable[map] = edge

    local backTable = db.transitions[map] or {}
    db.transitions[map] = backTable
    local back = backTable[previous.map] or { count = 0 }
    back.fromX, back.fromY = x, y
    back.toX, back.toY = previous.x, previous.y
    back.count = (back.count or 0) + 1
    back.last = time()
    back.source = "learned"
    backTable[previous.map] = back

    AddLog("crossing", {
        from = previous.map,
        to = map,
        fromX = previous.x,
        fromY = previous.y,
        toX = x,
        toY = y,
        distance = distance,
    })

    if edge.count == 1 then
        Print(string.format("learned a real crossing: %s -> %s at %s.",
            MapName(previous.map) or previous.map,
            MapName(map) or map,
            CoordText(previous.x, previous.y)))
    end
end

--[[ Corridor backbones -----------------------------------------------------
    Compact entrance->exit walking routes generated offline from the SPF
    navigation maps. They are not the navmesh: each zone stores only its
    connection endpoints and the polylines between them.
--------------------------------------------------------------------------]]
local function CorridorKey(x, y)
    return string.format("%.4f,%.4f", x, y)
end

local function UnpackCorridor(flat)
    local points = {}
    for i = 1, #flat, 2 do
        points[#points + 1] = { x = flat[i], y = flat[i + 1] }
    end
    return points
end

local function NearestCorridorEndpoint(zone, x, y)
    local best, bestDistance
    for _, endpoint in ipairs(zone.endpoints or {}) do
        local dx, dy = endpoint.x - x, endpoint.y - y
        local distance = dx * dx + dy * dy
        if not bestDistance or distance < bestDistance then
            best, bestDistance = endpoint, distance
        end
    end
    return best, bestDistance
end

function NodeTaxi:FindCorridor(mapID, fromX, fromY, toX, toY)
    local data = ns.CorridorData and ns.CorridorData.zones[mapID]
    if not (data and data.paths and data.endpoints) then
        return nil
    end

    local fromKey = CorridorKey(fromX, fromY)
    local toKey = CorridorKey(toX, toY)
    local flat = data.paths[fromKey .. "|" .. toKey]
    if flat then
        return UnpackCorridor(flat), { x = fromX, y = fromY }, { x = toX, y = toY }, true, true
    end

    -- First and last legs usually start or end somewhere inside the zone,
    -- not on a Carbonite connection. Use the nearest published endpoint and
    -- let the caller draw a short connector.
    local fromEndpoint, fromDistance = NearestCorridorEndpoint(data, fromX, fromY)
    local toEndpoint, toDistance = NearestCorridorEndpoint(data, toX, toY)
    if not (fromEndpoint and toEndpoint) then
        return nil
    end
    -- Do not attach a corridor through a long invented connector.
    if fromDistance > 0.04 or toDistance > 0.04 then
        return nil
    end
    if fromEndpoint.key == toEndpoint.key then
        return nil
    end

    flat = data.paths[fromEndpoint.key .. "|" .. toEndpoint.key]
    if not flat then
        return nil
    end
    return UnpackCorridor(flat),
        { x = fromEndpoint.x, y = fromEndpoint.y, key = fromEndpoint.key },
        { x = toEndpoint.x, y = toEndpoint.y, key = toEndpoint.key },
        false, false
end

local function ProjectOnCorridor(points, x, y)
    local best = { distanceSq = math.huge }
    local progress = 0
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local lengthSq = dx * dx + dy * dy
        local length = math.sqrt(lengthSq)
        local t = 0
        if lengthSq > 0 then
            t = ((x - a.x) * dx + (y - a.y) * dy) / lengthSq
            t = math.max(0, math.min(1, t))
        end
        local px, py = a.x + dx * t, a.y + dy * t
        local ox, oy = x - px, y - py
        local distanceSq = ox * ox + oy * oy
        if distanceSq < best.distanceSq then
            best = {
                distanceSq = distanceSq,
                segment = i,
                t = t,
                x = px,
                y = py,
                dx = x - px,
                dy = y - py,
                progress = progress + t * length,
            }
        end
        progress = progress + length
    end
    best.total = progress
    best.distance = math.sqrt(best.distanceSq)
    return best
end

-- Turn a corridor into a visible node-to-node path: follow the corridor as
-- the reference, insert each selected resource node at its projection, and
-- connect the player/target with short connectors. The corridor itself is
-- never drawn.
local function TrimCorridor(corridor, progress)
    local total = 0
    for i = 1, #corridor - 1 do
        local dx = corridor[i + 1].x - corridor[i].x
        local dy = corridor[i + 1].y - corridor[i].y
        local length = math.sqrt(dx * dx + dy * dy)
        if progress <= total + length or i == #corridor - 1 then
            local t = length > 0 and math.max(0, math.min(1, (progress - total) / length)) or 0
            local start = {
                x = corridor[i].x + dx * t,
                y = corridor[i].y + dy * t,
            }
            local trimmed = { start }
            for j = i + 1, #corridor do
                trimmed[#trimmed + 1] = corridor[j]
            end
            return trimmed, start
        end
        total = total + length
    end
    return { corridor[#corridor] }, corridor[#corridor]
end

function NodeTaxi:BuildCorridorLeg(leg)
    if not leg.corridorPoints then
        return false
    end

    local corridor = leg.corridorPoints
    local zoneWidth, zoneHeight = self:GetZoneSize(leg.map)
    local allNodes = leg.allNodes or self:NodeListForMap(leg.map)
    leg.allNodes = allNodes
    local maxOffset = math.min(settings.corridor, settings.spur or 100)
    local neighborYards = settings.spur or 100

    local function yardsBetween(a, b)
        if zoneWidth and zoneHeight then
            local dx, dy = (a.x - b.x) * zoneWidth, (a.y - b.y) * zoneHeight
            return math.sqrt(dx * dx + dy * dy)
        end
        local dx, dy = a.x - b.x, a.y - b.y
        return math.sqrt(dx * dx + dy * dy) * 1000
    end

    local cumulative = { 0 }
    for i = 2, #corridor do
        local dx = corridor[i].x - corridor[i - 1].x
        local dy = corridor[i].y - corridor[i - 1].y
        cumulative[i] = cumulative[i - 1] + math.sqrt(dx * dx + dy * dy)
    end
    local totalProgress = cumulative[#corridor]

    local function PointAtProgress(progress)
        progress = math.max(0, math.min(totalProgress, progress))
        for i = 1, #corridor - 1 do
            if progress <= cumulative[i + 1] then
                local span = cumulative[i + 1] - cumulative[i]
                local t = span > 0 and (progress - cumulative[i]) / span or 0
                return {
                    x = corridor[i].x + (corridor[i + 1].x - corridor[i].x) * t,
                    y = corridor[i].y + (corridor[i + 1].y - corridor[i].y) * t,
                }
            end
        end
        return { x = corridor[#corridor].x, y = corridor[#corridor].y }
    end

    local candidates = {}
    for _, node in ipairs(allNodes) do
        local projection = ProjectOnCorridor(corridor, node.x, node.y)
        local offsetYards = projection.distance * 1000
        if zoneWidth and zoneHeight then
            offsetYards = math.sqrt(
                (projection.dx * zoneWidth) ^ 2 + (projection.dy * zoneHeight) ^ 2)
        end
        if offsetYards <= maxOffset then
            candidates[#candidates + 1] = {
                node = node,
                projection = projection,
                offsetYards = offsetYards,
            }
        end
    end
    table.sort(candidates, function(a, b)
        return a.projection.progress < b.projection.progress
    end)

    local preferred = {}
    for _, node in ipairs(leg.preserveNodes or {}) do
        preferred[string.format("%.4f,%.4f,%s", node.x, node.y, tostring(node.kind))] = true
    end

    -- Cluster first, then score. Nodes within the branch radius form one
    -- cluster; a cluster can start only if at least one member is within the
    -- corridor deviation limit. Clusters are ranked by density/span so an
    -- early sparse cluster cannot consume the node budget before a dense one.
    local parent = {}
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    local function union(a, b)
        local ra, rb = find(a), find(b)
        if ra ~= rb then
            parent[rb] = ra
        end
    end
    for i = 1, #candidates do
        parent[i] = i
    end
    for i = 1, #candidates do
        for j = i + 1, #candidates do
            if yardsBetween(candidates[i].node, candidates[j].node) <= neighborYards then
                union(i, j)
            end
        end
    end

    local groups = {}
    for i = 1, #candidates do
        local root = find(i)
        groups[root] = groups[root] or {}
        groups[root][#groups[root] + 1] = candidates[i]
    end

    local clusters = {}
    for _, group in pairs(groups) do
        local startable
        for _, candidate in ipairs(group) do
            if candidate.offsetYards <= maxOffset then
                if not startable or candidate.projection.progress < startable.projection.progress then
                    startable = candidate
                end
            end
        end
        if startable then
            -- Enter at the earliest startable node, merge at the latest
            -- corridor projection. For normal cluster sizes, solve the open
            -- path exactly (Held-Karp) so the branch is the shortest possible
            -- entry -> nodes -> merge walk instead of a 2-opt approximation.
            local merge = startable
            for _, candidate in ipairs(group) do
                if candidate.projection.progress > merge.projection.progress then
                    merge = candidate
                end
            end
            local middle = {}
            for _, candidate in ipairs(group) do
                if candidate ~= startable and candidate ~= merge then
                    middle[#middle + 1] = candidate
                end
            end

            local ordered = { startable }
            local n = #middle
            if n > 0 and n <= 8 then
                local size = 2 ^ n
                local dp, prev = {}, {}
                for mask = 0, size - 1 do
                    dp[mask], prev[mask] = {}, {}
                end
                for j = 1, n do
                    local mask = 2 ^ (j - 1)
                    dp[mask][j] = yardsBetween(startable.node, middle[j].node)
                end
                for mask = 1, size - 1 do
                    for j = 1, n do
                        local current = dp[mask][j]
                        if current then
                            for k = 1, n do
                                if math.floor(mask / 2 ^ (k - 1)) % 2 == 0 then
                                    local nextMask = mask + 2 ^ (k - 1)
                                    local candidate = current + yardsBetween(middle[j].node, middle[k].node)
                                    if not dp[nextMask][k] or candidate < dp[nextMask][k] then
                                        dp[nextMask][k] = candidate
                                        prev[nextMask][k] = j
                                    end
                                end
                            end
                        end
                    end
                end
                local full = size - 1
                local bestLast, bestDistance
                for j = 1, n do
                    if dp[full][j] then
                        local candidate = dp[full][j] + yardsBetween(middle[j].node, merge.node)
                        if not bestDistance or candidate < bestDistance then
                            bestLast, bestDistance = j, candidate
                        end
                    end
                end
                if bestLast then
                    local reverse = {}
                    local mask, j = full, bestLast
                    while j do
                        reverse[#reverse + 1] = middle[j]
                        local previous = prev[mask][j]
                        mask = mask - 2 ^ (j - 1)
                        j = previous
                    end
                    for i = #reverse, 1, -1 do
                        ordered[#ordered + 1] = reverse[i]
                    end
                else
                    for _, candidate in ipairs(middle) do
                        ordered[#ordered + 1] = candidate
                    end
                end
            else
                -- Large cluster fallback: nearest-neighbour, then 2-opt the
                -- middle with entry/merge pinned.
                local remaining = {}
                for _, candidate in ipairs(middle) do
                    remaining[#remaining + 1] = candidate
                end
                local current = startable
                while #remaining > 0 do
                    local best, bestIndex, bestDistance
                    for i, candidate in ipairs(remaining) do
                        local distance = yardsBetween(current.node, candidate.node)
                        if not bestDistance or distance < bestDistance then
                            best, bestIndex, bestDistance = candidate, i, distance
                        end
                    end
                    ordered[#ordered + 1] = best
                    table.remove(remaining, bestIndex)
                    current = best
                end
                if #ordered >= 3 then
                    local function orderLength()
                        local total = 0
                        for i = 2, #ordered do
                            total = total + yardsBetween(ordered[i - 1].node, ordered[i].node)
                        end
                        return total
                    end
                    local bestLength = orderLength()
                    for _ = 1, 3 do
                        local improved = false
                        for first = 2, #ordered - 2 do
                            for last = first + 1, #ordered - 1 do
                                local a, b = first, last
                                while a < b do
                                    ordered[a], ordered[b] = ordered[b], ordered[a]
                                    a, b = a + 1, b - 1
                                end
                                local candidateLength = orderLength()
                                if candidateLength + 1e-9 < bestLength then
                                    bestLength = candidateLength
                                    improved = true
                                else
                                    a, b = first, last
                                    while a < b do
                                        ordered[a], ordered[b] = ordered[b], ordered[a]
                                        a, b = a + 1, b - 1
                                    end
                                end
                            end
                        end
                        if not improved then
                            break
                        end
                    end
                end
            end
            if merge ~= startable then
                ordered[#ordered + 1] = merge
            end

            local maxProgress = merge.projection.progress
            local span = math.max(0, maxProgress - startable.projection.progress)
            local locked = 0
            for _, candidate in ipairs(group) do
                local key = string.format("%.4f,%.4f,%s",
                    candidate.node.x, candidate.node.y, tostring(candidate.node.kind))
                if preferred[key] then
                    locked = locked + 1
                end
            end
            clusters[#clusters + 1] = {
                entryProgress = startable.projection.progress,
                mergeProgress = maxProgress,
                nodes = ordered,
                locked = locked,
                score = #group / (1 + span * 1000),
            }
        end
    end

    table.sort(clusters, function(a, b)
        local aLocked, bLocked = (a.locked or 0) > 0, (b.locked or 0) > 0
        if aLocked ~= bLocked then
            return aLocked
        end
        if a.score == b.score then
            return a.entryProgress < b.entryProgress
        end
        return a.score > b.score
    end)

    local branches = {}
    local selectedCount = 0
    local selectedClusters = {}
    for _, cluster in ipairs(clusters) do
        if selectedCount >= settings.maxNodes then
            break
        end
        local overlaps = false
        for _, other in ipairs(selectedClusters) do
            if cluster.entryProgress < other.mergeProgress
                and cluster.mergeProgress > other.entryProgress then
                overlaps = true
                break
            end
        end
        if overlaps then
            -- Keep the route forward; skip a cluster whose corridor span
            -- overlaps one already selected.
        else
        local take = {}
        local slots = math.min(settings.maxNodes - selectedCount, settings.cluster or 4)
        for _, candidate in ipairs(cluster.nodes) do
            if #take < slots then
                take[#take + 1] = candidate
            end
        end
        if #take > 0 then
            local mergeProgress = take[1].projection.progress
            for _, candidate in ipairs(take) do
                if candidate.projection.progress > mergeProgress then
                    mergeProgress = candidate.projection.progress
                end
            end
            branches[#branches + 1] = {
                entryProgress = take[1].projection.progress,
                mergeProgress = mergeProgress,
                nodes = take,
            }
            selectedCount = selectedCount + #take
            selectedClusters[#selectedClusters + 1] = {
                entryProgress = take[1].projection.progress,
                mergeProgress = mergeProgress,
            }
        end
        end
    end

    table.sort(branches, function(a, b)
        return a.entryProgress < b.entryProgress
    end)

    local nodesOut = {}
    for _, branch in ipairs(branches) do
        for _, candidate in ipairs(branch.nodes) do
            nodesOut[#nodesOut + 1] = candidate.node
        end
    end

    if #nodesOut == 0 then
        leg.nodes = {}
        leg.plan = {
            nodes = {},
            length = 0,
            direct = 0,
            inCorridor = #candidates,
        }
        local route = { { x = leg.startX, y = leg.startY } }
            local function push(x, y)
                local last = route[#route]
                if not last or math.abs(last.x - x) > 0.0001 or math.abs(last.y - y) > 0.0001 then
                    route[#route + 1] = { x = x, y = y }
                end
            end
            if leg.corridorStart then push(leg.corridorStart.x, leg.corridorStart.y) end
            for _, point in ipairs(corridor) do push(point.x, point.y) end
            if leg.corridorEnd then push(leg.corridorEnd.x, leg.corridorEnd.y) end
            push(leg.destX, leg.destY)
            local length = 0
            for i = 2, #route do
                local dx, dy = route[i].x - route[i - 1].x, route[i].y - route[i - 1].y
                length = length + math.sqrt(dx * dx + dy * dy)
            end
            leg.routePoints = route
            leg.plan.length = length * 1000
            leg.plan.direct = math.sqrt((leg.destX - leg.startX) ^ 2 + (leg.destY - leg.startY) ^ 2) * 1000
        return true
    end

    local route = {}
    local function Add(x, y, node)
        local previous = route[#route]
        if previous and math.abs(previous.x - x) < 0.0001 and math.abs(previous.y - y) < 0.0001 then
            return
        end
        route[#route + 1] = { x = x, y = y, node = node }
    end

    local function CatmullRom(points, steps)
        local function at(index)
            if index < 1 then return points[1] end
            if index > #points then return points[#points] end
            return points[index]
        end
        for index = 1, #points - 1 do
            local p0, p1, p2, p3 = at(index - 1), at(index), at(index + 1), at(index + 2)
            for step = 0, steps - 1 do
                local t = step / steps
                local t2, t3 = t * t, t * t * t
                local x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                    + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                    + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                local y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                    + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                    + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                Add(x, y)
            end
        end
        Add(points[#points].x, points[#points].y)
    end

    Add(leg.startX, leg.startY)
    if leg.corridorStart then
        Add(leg.corridorStart.x, leg.corridorStart.y)
    end
    Add(corridor[1].x, corridor[1].y)
    local corridorIndex = 1

    local function advanceCursor(progress)
        while corridorIndex < #corridor and cumulative[corridorIndex + 1] <= progress + 1e-9 do
            corridorIndex = corridorIndex + 1
        end
    end

    local function appendCorridorTo(progress)
        progress = math.max(0, math.min(totalProgress, progress))
        while corridorIndex < #corridor and cumulative[corridorIndex + 1] <= progress - 1e-9 do
            corridorIndex = corridorIndex + 1
            Add(corridor[corridorIndex].x, corridor[corridorIndex].y)
        end
        local point = PointAtProgress(progress)
        Add(point.x, point.y)
        advanceCursor(progress)
    end

    for _, branch in ipairs(branches) do
        appendCorridorTo(branch.entryProgress)
        local sweep = { { x = PointAtProgress(branch.entryProgress).x, y = PointAtProgress(branch.entryProgress).y } }
        for _, candidate in ipairs(branch.nodes) do
            sweep[#sweep + 1] = { x = candidate.node.x, y = candidate.node.y, node = candidate.node }
        end
        local merge = PointAtProgress(branch.mergeProgress)
        sweep[#sweep + 1] = { x = merge.x, y = merge.y }
        CatmullRom(sweep, 6)
        advanceCursor(branch.mergeProgress)
    end

    appendCorridorTo(totalProgress)
    if leg.corridorEnd then
        Add(leg.corridorEnd.x, leg.corridorEnd.y)
    end
    Add(leg.destX, leg.destY)

    local length = 0
    for i = 2, #route do
        local dx, dy = route[i].x - route[i - 1].x, route[i].y - route[i - 1].y
        length = length + math.sqrt(dx * dx + dy * dy)
    end
    local ddx, ddy = leg.destX - leg.startX, leg.destY - leg.startY
    local direct = math.sqrt(ddx * ddx + ddy * ddy) * 1000

    leg.routePoints = route
    leg.nodes = nodesOut
    leg.plan = {
        nodes = nodesOut,
        length = length * 1000,
        direct = direct,
        inCorridor = #candidates,
    }
    return true
end

-- A leg with no generated corridor (transport, or an uncovered zone) still
-- needs a visible node line. Use the real leg endpoints and the selected
-- nodes; this is deliberately a fallback, not a corridor substitute.
function NodeTaxi:BuildFallbackLeg(leg)
    local route = { { x = leg.startX, y = leg.startY } }
    local nodes = leg.nodes or {}
    for _, node in ipairs(nodes) do
        route[#route + 1] = { x = node.x, y = node.y, node = node }
    end
    local last = route[#route]
    if math.abs(last.x - leg.destX) > 0.0001 or math.abs(last.y - leg.destY) > 0.0001 then
        route[#route + 1] = { x = leg.destX, y = leg.destY }
    end

    local length = 0
    for i = 2, #route do
        local dx = route[i].x - route[i - 1].x
        local dy = route[i].y - route[i - 1].y
        length = length + math.sqrt(dx * dx + dy * dy)
    end
    local dx, dy = leg.destX - leg.startX, leg.destY - leg.startY
    leg.routePoints = route
    leg.plan = {
        nodes = nodes,
        length = length * 1000,
        direct = math.sqrt(dx * dx + dy * dy) * 1000,
        inCorridor = #nodes,
    }
    return true
end

function NodeTaxi:AttachCorridors(legs)
    local attached = 0
    for i, leg in ipairs(legs) do
        leg.isFirst = (i == 1)
        leg.isLast = (i == #legs)
        local path, startPoint, endPoint, exactStart, exactEnd = self:FindCorridor(
            leg.map, leg.startX, leg.startY, leg.destX, leg.destY)
        if path then
            leg.corridorPoints = path
            leg.corridorStart = startPoint
            leg.corridorEnd = endPoint
            leg.corridorExactStart = exactStart
            leg.corridorExactEnd = exactEnd
            if i == 1 and not exactStart then
                leg.corridorConnectorStart = true
            end
            if i == #legs and not exactEnd then
                leg.corridorConnectorEnd = true
            end
            self:BuildCorridorLeg(leg)
            attached = attached + 1
        else
            self:BuildFallbackLeg(leg)
        end
    end
    return attached
end

function NodeTaxi:ZonesUnderMap(mapID)
    local zones, seen = {}, {}
    local function walk(id)
        if not id or seen[id] then
            return
        end
        seen[id] = true
        local info = GetMapInfoRaw(id)
        if info and info.mapType == 3 then
            zones[#zones + 1] = id
            return
        end
        if C_Map and C_Map.GetMapChildrenInfo then
            local ok, children = pcall(C_Map.GetMapChildrenInfo, id, nil, true)
            if ok and type(children) == "table" then
                for _, child in ipairs(children) do
                    if type(child) == "table" and child.mapID then
                        walk(child.mapID)
                    end
                end
            end
        end
    end
    walk(mapID)
    return zones
end

function NodeTaxi:NodesForTopMap(mapID)
    InitSettingsIfNeeded()
    local key = table.concat({
        tostring(mapID),
        self:GetEffectiveKind(),
        tostring(self.nodeRevision or 0),
        self.SeedData and self.SeedData.version or "",
    }, ":")
    if self.worldNodeCache and self.worldNodeCache.key == key then
        return self.worldNodeCache.lists
    end

    local zones = self:ZonesUnderMap(mapID)
    if #zones == 0 then
        -- Fallback for clients without GetMapChildrenInfo: derive the zones
        -- from the seed/learned data and their parent chain.
        local info = GetMapInfoRaw(mapID)
        if info and info.mapType ~= 3 then
            local seen = {}
            local function consider(zone)
                if seen[zone] then
                    return
                end
                seen[zone] = true
                local current = zone
                for _ = 1, 6 do
                    if current == mapID then
                        zones[#zones + 1] = zone
                        return
                    end
                    local mapInfo = GetMapInfoRaw(current)
                    current = mapInfo and mapInfo.parentMapID
                    if not current then
                        return
                    end
                end
            end
            if self.SeedData then
                for zone in pairs(self.SeedData.herbs or {}) do consider(zone) end
                for zone in pairs(self.SeedData.mines or {}) do consider(zone) end
            end
            for zone in pairs(db.nodes or {}) do consider(zone) end
        end
    end

    local lists = {}
    for _, zone in ipairs(zones) do
        local nodes = self:NodeListForMap(zone)
        if #nodes > 0 then
            lists[#lists + 1] = { map = zone, nodes = nodes }
        end
    end
    self.worldNodeCache = { key = key, lists = lists }
    return lists
end

function NodeTaxi:BuildRoute(announce)
    InitSettingsIfNeeded()

    local dest = state.dest
    if not dest then
        if announce then
            Print("no TomTom arrow target. Set a TomTom waypoint first (or use /nt preview).")
        end
        return false
    end

    local playerMap, px, py = self:GetPlayerZone()
    if not playerMap or not px then
        if announce then
            Print("cannot read your position right now.")
        end
        return false
    end

    local width, height = self:GetZoneSize(playerMap)
    if not width then
        if announce then
            Print("HereBeDragons has no size for " .. (MapName(playerMap) or playerMap) .. ", cannot plan.")
        end
        return false
    end

    local destInfo = GetMapInfoRaw(dest.map)
    if destInfo and destInfo.mapType ~= 3 then
        self:ClearRoute(nil, true)
        if announce then
            Print(string.format(
                "the TomTom target is on %s, which is not a zone map. Zoom into the destination zone and set the waypoint there.",
                MapName(dest.map) or ("map " .. dest.map)))
        end
        return false
    end

    local planDest = { x = dest.x, y = dest.y }
    local cross

    if playerMap ~= dest.map then
        local zoneRoute = self:FindZoneRoute(playerMap, dest.map, px, py)
        if not zoneRoute then
            self:ClearRoute(nil, true)
            if announce then
                local known = self:GetTransitionEdges(playerMap)
                local names = {}
                for target in pairs(known) do
                    names[#names + 1] = MapName(target) or ("map " .. target)
                end
                table.sort(names)
                Print(string.format(
                    "no known crossing from %s toward %s yet. Walk through a border or portal once with NodeTaxi loaded and it will learn the real point.%s",
                    MapName(playerMap) or ("map " .. playerMap),
                    MapName(dest.map) or ("map " .. dest.map),
                    #names > 0 and (" Known exits: " .. table.concat(names, ", ") .. ".") or ""))
            end
            return false
        end

        local edge = self:GetTransitionEdges(playerMap, px, py)[zoneRoute[2]]
        if not (edge and edge.fromX) then
            self:ClearRoute(nil, true)
            if announce then
                Print("the zone route needs a crossing that has no coordinate yet.")
            end
            return false
        end

        cross = {
            zones = #zoneRoute,
            nextMap = zoneRoute[2],
            edge = edge,
            route = zoneRoute,
            source = edge.source,
            name = edge.name,
            path = self:BuildCrossPath(zoneRoute, playerMap, px, py, dest),
        }
        planDest = { x = edge.fromX, y = edge.fromY }
    end

    local nodes = self:NodeListForMap(playerMap)
    local plan, err = Route.Plan({
        start = { x = px, y = py },
        dest = { x = planDest.x, y = planDest.y },
        nodes = nodes,
        width = width,
        height = height,
        corridor = settings.corridor,
        maxNodes = settings.maxNodes,
        detour = settings.detour,
    })

    if not plan then
        if announce then
            Print("route planning failed: " .. tostring(err))
        end
        return false
    end

    if #plan.nodes == 0 and not cross then
        self:ClearRoute(nil, true)
        if announce then
            if plan.inCorridor > 0 then
                Print(string.format(
                    "found %d known node(s) on the way, but none fit the detour budget. Try /nt detour 2.5 or /nt max %d.",
                    plan.inCorridor, settings.maxNodes))
            else
                Print(string.format(
                    "no known nodes in the corridor (%d known in %s, including baked data). Farm a few nodes or use /nt here.",
                    #nodes, MapName(playerMap) or "this zone"))
            end
        end
        return false
    end

    -- Build the full display plan, not just this leg. Every zone on the
    -- route gets its own entry point, exit point and selected nodes, so the
    -- continent map can show the resource path all the way to the target.
    local legs
    if cross then
        legs = { {
            map = playerMap,
            startX = px,
            startY = py,
            destX = planDest.x,
            destY = planDest.y,
            nodes = plan.nodes,
            allNodes = nodes,
            plan = plan,
        } }

        local entryX, entryY = cross.edge.toX, cross.edge.toY
        for i = 2, #cross.route do
            -- Map-link pins do not always provide a target-side coordinate.
            -- Do not invent one: stop the full leg display at the last real
            -- entry point instead.
            if not (entryX and entryY) then
                break
            end
            local mapID = cross.route[i]
            local startX, startY = entryX, entryY
            local edgeOut
            if i < #cross.route then
                edgeOut = self:GetTransitionEdges(mapID, startX, startY)[cross.route[i + 1]]
                if not (edgeOut and edgeOut.fromX) then
                    break
                end
            end

            local destX = edgeOut and edgeOut.fromX or dest.x
            local destY = edgeOut and edgeOut.fromY or dest.y
            local legPlan
            local legNodes = self:NodeListForMap(mapID)
            local legWidth, legHeight = self:GetZoneSize(mapID)
            if legWidth then
                legPlan = Route.Plan({
                    start = { x = startX, y = startY },
                    dest = { x = destX, y = destY },
                    nodes = legNodes,
                    width = legWidth,
                    height = legHeight,
                    corridor = settings.corridor,
                    maxNodes = settings.maxNodes,
                    detour = settings.detour,
                })
            end

            legs[#legs + 1] = {
                map = mapID,
                startX = startX,
                startY = startY,
                destX = destX,
                destY = destY,
                nodes = legPlan and legPlan.nodes or {},
                allNodes = legNodes,
                plan = legPlan,
            }

            if edgeOut then
                entryX, entryY = edgeOut.toX, edgeOut.toY
            end
        end
    else
        legs = { {
            map = playerMap,
            startX = px,
            startY = py,
            destX = planDest.x,
            destY = planDest.y,
            nodes = plan.nodes,
            allNodes = nodes,
            plan = plan,
        } }
    end

    local totalNodes = 0
    for i = 1, #legs do
        totalNodes = totalNodes + #(legs[i].nodes or {})
    end

    local corridorLegs = 0
    if cross then
        corridorLegs = self:AttachCorridors(legs)
        cross.corridorLegs = corridorLegs
        if legs[1] and legs[1].plan then
            plan = legs[1].plan
        end
        totalNodes = 0
        for i = 1, #legs do
            totalNodes = totalNodes + #(legs[i].nodes or {})
        end
    end

    local routeDest
    if cross then
        local nextName = (cross.nextMap and MapName(cross.nextMap))
            or MapName(dest.map)
            or "next zone"
        routeDest = {
            map = playerMap,
            x = planDest.x,
            y = planDest.y,
            title = "exit toward " .. nextName,
        }
    else
        routeDest = { map = dest.map, x = dest.x, y = dest.y, title = dest.title }
    end

    state.route = {
        map = playerMap,
        nodes = plan.nodes,
        dest = routeDest,
        index = 1,
        plan = plan,
        preview = false,
        cross = cross,
        crossPath = cross and cross.path or nil,
        legs = legs,
        totalNodes = totalNodes,
        finalDest = cross and dest or nil,
        planX = px,
        planY = py,
        planAt = GetTime(),
    }
    state.index = 1

    AddLog("route", {
        map = playerMap,
        x = px,
        y = py,
        tx = planDest.x,
        ty = planDest.y,
        nodes = #plan.nodes,
        len = plan.length,
        direct = plan.direct,
        cross = cross and (cross.nextMap or -1) or 0,
        zones = cross and cross.zones or 1,
        totalNodes = totalNodes,
        source = cross and cross.source or nil,
    })

    self:Redraw()

    if announce then
        local nextName = (cross and cross.nextMap and MapName(cross.nextMap))
            or MapName(dest.map)
            or "next zone"
        local extra = plan.length - plan.direct
        local percent = plan.direct > 0 and (extra / plan.direct * 100) or 0

        if cross then
            if #plan.nodes > 0 then
                Print(string.format(
                    "%d node%s this leg, %d across %d zones, toward the %s exit in %s (then %s): %.0f yd (direct %.0f, +%.0f%%)%s",
                    #plan.nodes, #plan.nodes == 1 and "" or "s",
                    totalNodes, #legs,
                    nextName, MapName(playerMap) or "this zone",
                    MapName(dest.map) or "target",
                    plan.length, plan.direct, percent,
                    " [" .. (cross.source == "seed"
                        and ("Carbonite " .. tostring(cross.edge.kind or "crossing") .. (cross.name and (": " .. cross.name) or ""))
                        or (cross.source == "link" and ("map link: " .. tostring(cross.name or "?")) or "learned crossing")) .. "]"))
            else
                Print(string.format(
                    "no known nodes on this leg; %d node%s across %d zones ahead, path to the %s exit in %s (then %s): %.0f yd%s",
                    totalNodes, totalNodes == 1 and "" or "s", #legs,
                    nextName, MapName(playerMap) or "this zone",
                    MapName(dest.map) or "target",
                    plan.length,
                    " [" .. (cross.source == "seed"
                        and ("Carbonite " .. tostring(cross.edge.kind or "crossing") .. (cross.name and (": " .. cross.name) or ""))
                        or (cross.source == "link" and ("map link: " .. tostring(cross.name or "?")) or "learned crossing")) .. "]"))
            end
        else
            Print(string.format(
                "%d node%s on the way to %s in %s: %.0f yd (direct %.0f, +%.0f%%)",
                plan.nodes and #plan.nodes or 0,
                (plan.nodes and #plan.nodes == 1) and "" or "s",
                CoordText(dest.x, dest.y),
                MapName(dest.map) or ("map " .. dest.map),
                plan.length, plan.direct, percent))
        end
    end

    return true
end


-- Re-evaluate the remaining route from where the player is now. Completed
-- nodes (those before route.index) are not fed back in, so the new order
-- cannot send you back to something you already collected.
-- Rolling refinement of the current corridor leg. The player's projection
-- trims the corridor ahead; unvisited nodes are re-clustered from there, so
-- newly nearby nodes can join the route as we move.
function NodeTaxi:RefreshCurrentLeg()
    local route = state.route
    local leg = route and route.legs and route.legs[1]
    if not (leg and leg.corridorPoints) then
        return false
    end

    local mapID, px, py = self:GetPlayerZone()
    if not mapID or mapID ~= leg.map or not px then
        return false
    end
    local remainingNodes = #route.nodes - math.max(0, (route.index or 1) - 1)
    if remainingNodes >= settings.maxNodes then
        -- Already at the per-leg budget. Keep the chosen route stable instead
        -- of swapping nodes as the player moves.
        return false
    end

    local projection = ProjectOnCorridor(leg.corridorPoints, px, py)
    if not projection or projection.progress <= 0.0001 then
        return false
    end

    local trimmed, corridorStart = TrimCorridor(leg.corridorPoints, projection.progress)
    local completed, selected = {}, {}
    for i = 1, math.min((route.index or 1) - 1, #route.nodes) do
        local node = route.nodes[i]
        completed[string.format("%.4f,%.4f,%s", node.x, node.y, tostring(node.kind))] = true
    end
    for _, node in ipairs(route.nodes or {}) do
        selected[string.format("%.4f,%.4f,%s", node.x, node.y, tostring(node.kind))] = true
    end

    local allNodes = {}
    local width, height = self:GetZoneSize(mapID)
    local nearbyNew = false
    local radius = settings.spur or 100
    for _, node in ipairs(self:NodeListForMap(mapID)) do
        local key = string.format("%.4f,%.4f,%s", node.x, node.y, tostring(node.kind))
        if not completed[key] then
            allNodes[#allNodes + 1] = node
            if not selected[key] and width and height then
                local dxp = (node.x - px) * width
                local dyp = (node.y - py) * height
                local dxc = (node.x - projection.x) * width
                local dyc = (node.y - projection.y) * height
                if dxp * dxp + dyp * dyp <= radius * radius
                    or dxc * dxc + dyc * dyc <= radius * radius then
                    nearbyNew = true
                end
            end
        end
    end
    if not nearbyNew then
        return false
    end

    leg.corridorPoints = trimmed
    leg.corridorStart = corridorStart
    leg.allNodes = allNodes
    leg.startX, leg.startY = px, py
    leg.isFirst = true
    local preserve = {}
    for i = route.index or 1, #route.nodes do
        preserve[#preserve + 1] = route.nodes[i]
    end
    leg.preserveNodes = preserve
    self:BuildCorridorLeg(leg)
    leg.preserveNodes = nil

    route.nodes = leg.nodes or {}
    route.plan = leg.plan or route.plan
    route.index = 1
    route.planX, route.planY, route.planAt = px, py, GetTime()
    route.totalNodes = #route.nodes
    for i = 2, #(route.legs or {}) do
        route.totalNodes = route.totalNodes + #(route.legs[i].nodes or {})
    end
    self:Redraw()
    return true
end

function NodeTaxi:ReplanFromCurrent(announce)
    local route = state.route
    if not route or route.preview then
        return false
    end
    if route.cross and route.legs and route.legs[1] and route.legs[1].corridorPoints then
        return self:RefreshCurrentLeg()
    end

    local mapID, px, py = self:GetPlayerZone()
    if not mapID or mapID ~= route.map then
        return false
    end
    if not route.dest or route.dest.map ~= mapID then
        return false
    end

    local remaining = {}
    for i = route.index, #route.nodes do
        remaining[#remaining + 1] = route.nodes[i]
    end
    if #remaining == 0 then
        return false
    end

    local width, height = self:GetZoneSize(mapID)
    if not width then
        return false
    end

    local plan = Route.Plan({
        start = { x = px, y = py },
        dest = { x = route.dest.x, y = route.dest.y },
        nodes = remaining,
        width = width,
        height = height,
        corridor = settings.corridor,
        maxNodes = settings.maxNodes,
        detour = settings.detour,
    })

    if not plan or #plan.nodes == 0 then
        return false
    end

    route.nodes = plan.nodes
    route.index = 1
    route.plan = plan
    route.planX, route.planY, route.planAt = px, py, GetTime()
    if route.legs and route.legs[1] then
        route.legs[1].nodes = plan.nodes
        route.legs[1].plan = plan
        route.legs[1].startX, route.legs[1].startY = px, py
        route.legs[1].destX, route.legs[1].destY = route.dest.x, route.dest.y
        local total = #plan.nodes
        for i = 2, #route.legs do
            total = total + #(route.legs[i].nodes or {})
        end
        route.totalNodes = total
    end
    state.index = 1

    self:Redraw()

    if announce then
        Print(string.format("route re-ordered: %d node(s), %.0f yd to go.", #plan.nodes, plan.length))
    end

    return true
end

local function ScheduleBuild(delay)
    buildToken = buildToken + 1
    local token = buildToken

    local function run()
        if token == buildToken then
            NodeTaxi:BuildRoute(true)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.4, run)
    else
        run()
    end
end

function NodeTaxi:OnArrowTargetChanged(uid)
    InitSettingsIfNeeded()

    local dest = DestFromUid(uid)
    if SameDest(dest, state.dest) then
        return
    end

    state.dest = dest

    if not dest then
        if state.route then
            self:ClearRoute("TomTom arrow target cleared; route stopped.", true)
        end
        return
    end

    if settings.auto then
        ScheduleBuild(0.4)
    elseif state.route then
        self:ClearRoute(nil, true)
        Print("TomTom target changed. /nt route to draw the new route.")
    else
        Print(string.format("TomTom target: %s in %s. /nt route to draw.",
            CoordText(dest.x, dest.y), MapName(dest.map) or ("map " .. dest.map)))
    end
end

function NodeTaxi:SkipNode()
    local route = state.route
    if not route then
        Print("no active route.")
        return
    end

    local skipped = route.nodes[route.index]
    route.index = route.index + 1
    if route.index > #route.nodes then
        Print("route complete.")
        self:ClearRoute(nil, true)
    else
        Print(string.format("skipped node %s, next is %d/%d.",
            skipped and CoordText(skipped.x, skipped.y) or "?", route.index, #route.nodes))
        if (settings.replan or 0) > 0 and self:ReplanFromCurrent(false) then
            return
        end
        self:Redraw()
    end
end

-- Diagnostic: what does NodeTaxi believe is around the player right now?
function NodeTaxi:ListNearby(radius)
    InitSettingsIfNeeded()
    radius = radius or 50

    local mapID, px, py = self:GetPlayerZone()
    if not mapID then
        Print("cannot read your position.")
        return
    end

    local width, height = self:GetZoneSize(mapID)
    if not width then
        Print("HereBeDragons has no size for " .. (MapName(mapID) or "this zone") .. ".")
        return
    end

    local nearby = {}
    for _, node in ipairs(self:NodeListForMap(mapID)) do
        local dx, dy = (node.x - px) * width, (node.y - py) * height
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= radius then
            nearby[#nearby + 1] = { node = node, distance = distance }
        end
    end

    table.sort(nearby, function(a, b)
        return a.distance < b.distance
    end)

    if #nearby == 0 then
        Print(string.format("no known nodes within %.0f yd in %s.", radius, MapName(mapID) or "this zone"))
        return
    end

    Print(string.format("%d known node(s) within %.0f yd in %s:", #nearby, radius, MapName(mapID) or "this zone"))
    for i = 1, math.min(#nearby, 10) do
        local entry = nearby[i]
        local node = entry.node
        local source = node.src or "learned"
        Print(string.format("  %s %.0f yd (%s) at %s%s",
            node.kind, entry.distance, source, CoordText(node.x, node.y),
            entry.distance <= math.max(settings.arrive or 18, node.coarse and 40 or 0) and "  <- you are on it" or ""))
    end
end

-- Older learned nodes predate node ids. Give them the id of the snapshot
-- node they sit on, so they use the specific resource art too.
function NodeTaxi:BackfillNodeIDs()
    local assigned = 0
    for mapID, list in pairs(db.nodes) do
        for _, node in ipairs(list) do
            if not node.nodeID and (node.kind == "herb" or node.kind == "ore") then
                local distance, _, _, nodeID = self:NearestSeed(mapID, node.x, node.y, node.kind)
                if distance and distance <= SEED_MATCH_YARDS and nodeID then
                    node.nodeID = nodeID
                    assigned = assigned + 1
                end
            end
        end
    end
    if assigned > 0 then
        AddLog("backfill", { assigned = assigned })
    end
    return assigned
end

-- Compare the spot you are standing on with the baked snapshot. Run this on
-- a live node you can see; the printed/logged distance tells us whether the
-- snapshot is accurate, merely coarse, or wrong for this zone.
function NodeTaxi:ValidateHere()
    local mapID, px, py = self:GetPlayerZone()
    if not mapID or not px then
        Print("cannot read your position.")
        return
    end

    local herbDistance, herbX, herbY = self:NearestSeed(mapID, px, py, "herb")
    local oreDistance, oreX, oreY = self:NearestSeed(mapID, px, py, "ore")
    local storedDistance, storedNode = self:NearestStored(mapID, px, py, nil)
    local zoneWidth, zoneHeight = self:GetZoneSize(mapID)

    local function describe(distance, x, y, label)
        if not distance then
            return label .. ": no baked node in this zone"
        end
        return string.format("%s: %.0f yd at %s", label, distance, CoordText(x, y))
    end

    Print(string.format("validate %s at %s:", MapName(mapID) or "?", CoordText(px, py)))
    Print("  " .. describe(herbDistance, herbX, herbY, "herb"))
    Print("  " .. describe(oreDistance, oreX, oreY, "ore"))
    Print("  nearest learned/imported: "
        .. (storedDistance and string.format("%.0f yd (%s)", storedDistance, storedNode.kind) or "none"))
    Print(string.format("  verdict: herb %s, ore %s",
        (herbDistance and herbDistance <= SEED_MATCH_YARDS) and "within snapshot tolerance" or "not matched",
        (oreDistance and oreDistance <= SEED_MATCH_YARDS) and "within snapshot tolerance" or "not matched"))

    AddLog("validate", {
        map = mapID,
        x = px,
        y = py,
        herb = herbDistance,
        herbX = herbX,
        herbY = herbY,
        ore = oreDistance,
        oreX = oreX,
        oreY = oreY,
        stored = storedDistance,
        w = zoneWidth,
        h = zoneHeight,
    })
end

-- Called a few times per second: collects nodes you reach and drops a route
-- that no longer belongs to the zone you are in.
function NodeTaxi:Tick()
    local route = state.route
    if not route then
        return
    end

    local mapID, px, py = self:GetPlayerZone()
    if not mapID or mapID ~= route.map then
        self:ClearRoute(nil, true)
        return
    end

    local node = route.nodes[route.index]
    if not node then
        return
    end

    local width, height = self:GetZoneSize(mapID)
    if not width then
        return
    end

    local function DistanceSquared(other)
        local dx, dy = (other.x - px) * width, (other.y - py) * height
        return dx * dx + dy * dy
    end

    local arrive = settings.arrive or 18
    if node.coarse then
        -- Snapshot/imported coordinates are two-decimal (about 100 yd in a
        -- large zone), so do not require standing exactly on the report.
        arrive = math.max(arrive, 40)
    end
    if DistanceSquared(node) <= arrive * arrive then
        route.index = route.index + 1
        if route.index > #route.nodes then
            Print("route complete - all nodes on the path were collected.")
            self:ClearRoute(nil, true)
        else
            Print(string.format("node %d/%d reached.", route.index - 1, #route.nodes))
            if (settings.replan or 0) > 0 and self:ReplanFromCurrent(false) then
                return
            end
            self:Redraw()
        end
        return
    end

    -- If you drove past a node (it is now well behind you and the next node
    -- is clearly closer), do not let the route get stuck on it.
    local nextNode = route.nodes[route.index + 1]
    if nextNode then
        local currentDistance = DistanceSquared(node)
        if currentDistance > 60 * 60 and DistanceSquared(nextNode) + 25 * 25 < currentDistance then
            route.index = route.index + 1
            if (settings.replan or 0) > 0 and self:ReplanFromCurrent(false) then
                return
            end
            self:Redraw()
            return
        end
    end

    -- Keep the remaining route re-evaluated as the player moves. The distance
    -- threshold keeps it from reordering every tick while you stand still or
    -- strafe, and the time guard caps how often a rebuild can happen.
    local replanDistance = settings.replan or 0
    if replanDistance > 0 and not route.preview then
        local movedX = (px - (route.planX or px)) * width
        local movedY = (py - (route.planY or py)) * height
        if (movedX * movedX + movedY * movedY) >= replanDistance * replanDistance then
            if (GetTime() - (route.planAt or 0)) >= 2 then
                self:ReplanFromCurrent(false)
            end
        end
    end
end

--[[ Node capture -----------------------------------------------------------]]
local function SpellName(spellID)
    spellID = tonumber(spellID)
    if not spellID then
        return nil
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and info.name then
            return info.name
        end
    end

    if GetSpellInfo then
        local name = GetSpellInfo(spellID)
        return name
    end

    return nil
end

local function BuildGatherNames()
    herbNames, oreNames = {}, {}

    local herb = SpellName(2366) -- Herb Gathering
    local ore = SpellName(2575)  -- Mining
    if herb then
        herbNames[herb] = true
    end
    if ore then
        oreNames[ore] = true
    end

    for name in pairs(db.learnedSpells.herb or {}) do
        herbNames[name] = true
    end
    for name in pairs(db.learnedSpells.ore or {}) do
        oreNames[name] = true
    end

    return herb, ore
end

local function OnSpellcastSucceeded(unit, castGUID, spellID)
    if unit ~= "player" or not spellID then
        return
    end

    local name = SpellName(spellID)
    if watchCasts then
        Print(string.format("cast %s (id %d)", tostring(name or "?"), spellID or 0))
    end
    if not name then
        return
    end

    local kind
    if herbNames[name] then
        kind = "herb"
    elseif oreNames[name] then
        kind = "ore"
    end
    if not kind then
        return
    end

    local now = GetTime()
    if now - lastCapture < 0.5 then
        return
    end
    lastCapture = now

    local mapID, x, y = NodeTaxi:GetPlayerZone()
    if not (mapID and x and y) then
        return
    end

    -- Compare with the snapshot before storing, so the log records whether
    -- this live node actually matches our baked data and by how much.
    local seedDistance, seedX, seedY, seedNodeID = NodeTaxi:NearestSeed(mapID, x, y, kind)
    local storedDistance = NodeTaxi:NearestStored(mapID, x, y, kind)
    local zoneWidth, zoneHeight = NodeTaxi:GetZoneSize(mapID)

    local node, duplicate = NodeTaxi:AddNode(mapID, x, y, kind)
    if node and seedNodeID and seedDistance and seedDistance <= SEED_MATCH_YARDS then
        -- Inherit the specific node type (Copper Vein, Peacebloom, ...) when
        -- the live gather sits on the snapshot's node.
        node.nodeID = seedNodeID
    end

    local verdict = "novel"
    if seedDistance then
        if seedDistance <= SEED_MATCH_YARDS then
            verdict = "matched"
        elseif seedDistance <= SEED_MATCH_YARDS * 2 then
            verdict = "near"
        end
    end

    AddLog("gather", {
        spell = name,
        id = spellID,
        map = mapID,
        x = x,
        y = y,
        kind = kind,
        dup = duplicate or false,
        count = node and node.count,
        seed = seedDistance,
        sx = seedX,
        sy = seedY,
        stored = storedDistance,
        verdict = verdict,
        nodeID = node and node.nodeID,
        w = zoneWidth,
        h = zoneHeight,
    })

    if settings.logChat then
        local seedText
        if seedDistance then
            seedText = string.format("nearest baked %.0f yd", seedDistance)
        else
            seedText = "no baked node for this kind in zone"
        end
        Print(string.format("%s %s at %s (%s; %s)",
            duplicate and "updated" or "learned", kind, CoordText(x, y), verdict, seedText))
    end
end

--[[ Commands ---------------------------------------------------------------]]
local function PrintHelp()
    Print("dashed routes through known resource nodes, without touching TomTom:")
    Print("  /nt route          build a route to the current TomTom arrow target")
    Print("  /nt stop           clear the drawn route")
    Print("  /nt dest           show the TomTom arrow target")
    Print("  /nt here [herb|ore] remember a node where you stand")
    Print("  /nt nodes          node counts")
    Print("  /nt crossings      real zone crossings known from this zone")
    Print("  /nt near [yd]      list known nodes around you, with their source")
    Print("  /nt validate       compare this spot with the baked snapshot")
    Print("  /nt log [n|clear|chat on|off]  persistent diagnostic log")
    Print("  /nt import gathermate2  copy nodes out of your local GatherMate2 data")
    Print("  /nt seed           show the baked Forever snapshot version")
    Print("  /nt skip           skip the current node")
    Print("  /nt preview        draw a synthetic route to check the overlay")
    Print("  /nt width 300      corridor half-width in yards")
    Print("  /nt max 8          maximum nodes per route")
    Print("  /nt detour 1.8     route length / direct distance")
    Print("  /nt arrive 18      yards at which a node is collected")
    Print("  /nt replan 30      yards moved before the remaining route is re-ordered (0 = off)")
    Print("  /nt ring 100       yards at which a node marker becomes a hollow ring (0 = off)")
    Print("  /nt auto on|off    rebuild when the arrow target changes")
    Print("  /nt allnodes on|off show every known node under the displayed map")
    Print("  /nt spur 100      max yards a node may pull away from the route")
    Print("  /nt cluster 4     max nodes from one nearby cluster")
    Print("  /nt kind auto|herb|ore|both  node filter; auto follows your tracking")
    Print("  /nt debug          diagnostic information")
    Print("  /nt learn herb|ore <spellID>  teach a gather spell by hand")
    Print("  /nt watch          log successful casts (to verify node learning)")
    Print("  /nt clear yes      delete every learned node")
end

local function PrintStatus()
    InitSettingsIfNeeded()
    local playerMap = NodeTaxi:GetPlayerZone()
    Print(string.format("settings: corridor %.0f yd, max %.0f nodes, detour %.1fx, arrive %.0f yd, auto %s, allnodes %s, spur %.0f yd, cluster %.0f, kind %s, replan %.0f yd, ring %.0f yd",
        settings.corridor, settings.maxNodes, settings.detour, settings.arrive,
        settings.auto and "on" or "off", settings.allNodes and "on" or "off",
        settings.spur or 100, settings.cluster or 4, settings.kind, settings.replan, settings.ring))
    Print(string.format("tracking: active %s, filter %s -> using %s",
        tostring(NodeTaxi:DetectTracking() or "none"), settings.kind, NodeTaxi:GetEffectiveKind()))
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
            local info = C_Minimap.GetTrackingInfo(i)
            if info and info.active then
                Print(string.format("  active tracking: %s (spellID %s)",
                    tostring(info.name), tostring(info.spellID)))
            end
        end
    end
    Print(string.format("nodes: %d learned/imported in %s, %d total; baked: %d in this zone, %d total",
        NodeTaxi:NodeCount(playerMap), MapName(playerMap) or "?",
        NodeTaxi:NodeCount(nil), NodeTaxi:SeedCount(playerMap), NodeTaxi:SeedCount(nil)))

    local dest = state.dest
    if dest then
        Print(string.format("TomTom target: %s in %s", CoordText(dest.x, dest.y), MapName(dest.map) or "?"))
    else
        Print("TomTom target: none")
    end

    local route = state.route
    if route then
        Print(string.format("route: %d node(s), %d remaining%s, drawn on map/minimap",
            #route.nodes, math.max(0, #route.nodes - route.index + 1),
            route.cross and (" (leg toward " .. (MapName(route.cross.nextMap or route.dest.map) or "next zone") .. ")") or ""))
    end
end

local function PrintDebug()
    InitSettingsIfNeeded()
    local version, build, _, toc = GetBuildInfo()
    Print(string.format("NodeTaxi %s, client %s (%s), interface %s",
        AddonVersion(), tostring(version), tostring(build), tostring(toc)))

    local hbd = GetHBD()
    Print("HereBeDragons: " .. (hbd and "yes" or "NO (map sizes and minimap projection need it)"))

    local mapID, px, py = NodeTaxi:GetPlayerZone()
    if mapID then
        local width, height = NodeTaxi:GetZoneSize(mapID)
        Print(string.format("position: %s (%d) at %s%s",
            MapName(mapID) or "?", mapID, CoordText(px, py),
            width and string.format(", zone size %.0fx%.0f yd", width, height) or ", zone size unknown"))
    else
        Print("position: unavailable")
    end

    local info = NodeTaxi.OverlayDebugInfo and NodeTaxi:OverlayDebugInfo()
    Print("world map overlay: " .. (info and info.world or "not created yet"))
    Print("minimap overlay: " .. (info and info.minimap or "not created yet"))

    local sources = GetGatherMateSources()
    Print("GatherMate2 data: " .. (#sources > 0 and ("detected (" .. #sources .. " table(s))") or "not found"))

    Print(string.format("tracking: active %s, filter %s -> using %s",
        tostring(NodeTaxi:DetectTracking() or "none"), settings.kind, NodeTaxi:GetEffectiveKind()))
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
            local info = C_Minimap.GetTrackingInfo(i)
            if info and info.active then
                Print(string.format("  active tracking: %s (spellID %s)",
                    tostring(info.name), tostring(info.spellID)))
            end
        end
    end

    if NodeTaxi.SeedData then
        Print(string.format("baked seed: %s (%d nodes)", NodeTaxi.SeedData.version, NodeTaxi:SeedCount(nil)))
    else
        Print("baked seed: none")
    end

    Print(string.format("log: %d entries (chat %s); /nt log",
        #(db.log or {}), settings.logChat and "on" or "off"))

    local route = state.route
    if route and route.cross then
        Print(string.format("cross-zone leg: next %s via %s",
            tostring(MapName(route.cross.nextMap or route.dest.map) or "?"),
            (route.cross.source == "seed"
                and ("Carbonite " .. tostring(route.cross.edge.kind or "crossing") .. (route.cross.name and (": " .. route.cross.name) or ""))
                or (route.cross.source == "link" and ("map link " .. tostring(route.cross.name or "?")) or "learned crossing"))))
    end

    if NodeTaxi.NodeIcon then
        Print("icons: copper=" .. tostring(NodeTaxi.NodeIcon({ kind = "ore", nodeID = 201 }))
            .. " | peacebloom=" .. tostring(NodeTaxi.NodeIcon({ kind = "herb", nodeID = 401 })))
    end

    if C_Minimap and C_Minimap.GetViewRadius then
        Print("minimap view radius: " .. tostring(C_Minimap.GetViewRadius()))
    end

    NodeTaxi:PrintDestination()
end

function NodeTaxi:PrintDestination()
    local dest = state.dest
    if not dest then
        Print("TomTom arrow target: none")
        return
    end
    Print(string.format("TomTom arrow target: %s in %s (%s)",
        CoordText(dest.x, dest.y),
        MapName(dest.map) or ("map " .. dest.map),
        dest.title or "no title"))
end

function NodeTaxi:Preview()
    InitSettingsIfNeeded()

    local mapID, px, py = self:GetPlayerZone()
    if not mapID then
        Print("cannot read your position.")
        return
    end

    local dest = state.dest
    local tx, ty
    if dest and dest.map == mapID then
        tx, ty = dest.x, dest.y
    else
        tx, ty = px, py + 0.12
        if ty > 0.95 then
            ty = py - 0.12
        end
    end

    local nodes = {}
    local count = 6
    for i = 1, count do
        local t = i / (count + 1)
        local x = px + (tx - px) * t
        local y = py + (ty - py) * t
        local sway = ((i % 2 == 0) and 1 or -1) * 0.006
        x = math.max(0.03, math.min(0.97, x + sway * 0.6))
        y = math.max(0.03, math.min(0.97, y + sway))
        nodes[#nodes + 1] = {
            map = mapID,
            x = x,
            y = y,
            kind = (i % 3 == 0) and "ore" or "herb",
        }
    end

    state.route = {
        map = mapID,
        nodes = nodes,
        dest = { map = mapID, x = tx, y = ty },
        index = 1,
        preview = true,
        plan = { nodes = nodes, length = 0, direct = 0 },
    }
    state.index = 1

    self:Redraw()
    Print("preview drawn with synthetic nodes. Walk it, or /nt stop to clear. /nt route replaces it.")
end

local function OnOff(value)
    if value == "on" or value == "1" or value == "true" then
        return true
    elseif value == "off" or value == "0" or value == "false" then
        return false
    end
    return nil
end

local function HandleCommand(message)
    InitSettingsIfNeeded()

    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()

    if command == "" or command == "help" then
        PrintStatus()
        PrintHelp()

    elseif command == "route" then
        NodeTaxi:BuildRoute(true)

    elseif command == "stop" then
        if state.route then
            NodeTaxi:ClearRoute(nil, true)
            Print("route cleared.")
        else
            Print("no route to clear.")
        end

    elseif command == "dest" then
        NodeTaxi:PrintDestination()

    elseif command == "here" then
        local kind = rest:lower()
        if kind ~= "herb" and kind ~= "ore" then
            kind = "manual"
        end

        local mapID, x, y = NodeTaxi:GetPlayerZone()
        if not mapID then
            Print("cannot read your position.")
            return
        end
        local seedDistance
        if kind == "manual" then
            local herbDistance = NodeTaxi:NearestSeed(mapID, x, y, "herb")
            local oreDistance = NodeTaxi:NearestSeed(mapID, x, y, "ore")
            if herbDistance and oreDistance then
                seedDistance = math.min(herbDistance, oreDistance)
            else
                seedDistance = herbDistance or oreDistance
            end
        else
            seedDistance = NodeTaxi:NearestSeed(mapID, x, y, kind)
        end

        NodeTaxi:AddNode(mapID, x, y, kind)
        AddLog("manual", { map = mapID, x = x, y = y, kind = kind, seed = seedDistance })

        Print(string.format("remembered a %s node at %s (%s)%s.",
            kind, CoordText(x, y), MapName(mapID) or "?",
            seedDistance and string.format("; nearest baked %.0f yd", seedDistance) or ""))

    elseif command == "import" then
        local what = rest:lower()
        if what == "" or what == "gathermate2" or what == "gathermate" then
            NodeTaxi:ImportGatherMate2()
        else
            Print("usage: /nt import gathermate2")
        end

    elseif command == "seed" then
        local seed = NodeTaxi.SeedData
        if seed then
            Print(string.format("baked seed %s: %d node(s) across %d zone(s).",
                seed.version, NodeTaxi:SeedCount(nil), (function()
                    local zones = {}
                    for z in pairs(seed.herbs or {}) do zones[z] = true end
                    for z in pairs(seed.mines or {}) do zones[z] = true end
                    local n = 0
                    for _ in pairs(zones) do n = n + 1 end
                    return n
                end)()))
        else
            Print("this build has no baked seed (data.lua missing).")
        end

    elseif command == "near" then
        local radius = tonumber(rest) or 50
        if radius < 5 or radius > 500 then
            Print("usage: /nt near [5-500]  (default 50 yards)")
        else
            NodeTaxi:ListNearby(radius)
        end

    elseif command == "validate" then
        NodeTaxi:ValidateHere()

    elseif command == "log" then
        local argument = rest:lower()
        if argument == "clear" then
            db.log = {}
            Print("diagnostic log cleared.")
        elseif argument == "chat on" or argument == "chat off" then
            settings.logChat = (argument == "chat on")
            Print("gather chat logging " .. (settings.logChat and "on" or "off") .. ".")
        else
            local limit = math.floor(tonumber(argument) or 15)
            limit = math.max(1, math.min(limit, 100))
            local log = db.log or {}
            if #log == 0 then
                Print("diagnostic log is empty.")
            else
                Print(string.format("%d entries; last %d:", #log, math.min(limit, #log)))
                for i = math.max(1, #log - limit + 1), #log do
                    Print(FormatLogEntry(log[i]))
                end
            end
        end

    elseif command == "crossings" then
        local mapID = NodeTaxi:GetPlayerZone()
        local edges = mapID and NodeTaxi:GetTransitionEdges(mapID) or {}
        local list = {}
        for target, edge in pairs(edges) do
            list[#list + 1] = { target = target, edge = edge }
        end
        table.sort(list, function(a, b)
            return (MapName(a.target) or tostring(a.target)) < (MapName(b.target) or tostring(b.target))
        end)

        if #list == 0 then
            Print(string.format("no real crossings known from %s yet. Walk through a border or portal once and NodeTaxi will learn it.",
                mapID and (MapName(mapID) or mapID) or "this zone"))
        else
            Print(string.format("known real crossings from %s:", mapID and (MapName(mapID) or mapID) or "this zone"))
            for _, item in ipairs(list) do
                local edge = item.edge
                Print(string.format("  -> %s via %s at %s%s",
                    MapName(item.target) or ("map " .. item.target),
                    edge.source == "seed"
                        and ("Carbonite " .. tostring(edge.kind or "crossing") .. (edge.name and (": " .. edge.name) or ""))
                        or (edge.source == "link" and ("map link " .. tostring(edge.name or "?")) or "learned"),
                    CoordText(edge.fromX, edge.fromY),
                    edge.toX and (" (entry " .. CoordText(edge.toX, edge.toY) .. ")") or ""))
            end
        end

    elseif command == "nodes" then
        local mapID = NodeTaxi:GetPlayerZone()
        Print(string.format("%d learned/imported node(s) in %s, %d total; baked snapshot: %d in this zone.",
            NodeTaxi:NodeCount(mapID), MapName(mapID) or "this zone",
            NodeTaxi:NodeCount(nil), NodeTaxi:SeedCount(mapID)))

    elseif command == "skip" then
        NodeTaxi:SkipNode()

    elseif command == "preview" then
        NodeTaxi:Preview()

    elseif command == "width" then
        local value = tonumber(rest)
        if value and value >= 25 and value <= 3000 then
            settings.corridor = math.floor(value)
            Print("corridor half-width: " .. settings.corridor .. " yd. /nt route to apply.")
        else
            Print("usage: /nt width 300  (25-3000 yards)")
        end

    elseif command == "max" then
        local value = tonumber(rest)
        if value and value >= 1 and value <= 20 then
            settings.maxNodes = math.floor(value)
            Print("max nodes: " .. settings.maxNodes .. ". /nt route to apply.")
        else
            Print("usage: /nt max 8  (1-20)")
        end

    elseif command == "detour" then
        local value = tonumber(rest)
        if value and value >= 1 and value <= 5 then
            settings.detour = value
            Print(string.format("detour budget: %.2fx direct. /nt route to apply.", value))
        else
            Print("usage: /nt detour 1.8  (1.0-5.0)")
        end

    elseif command == "arrive" then
        local value = tonumber(rest)
        if value and value >= 5 and value <= 60 then
            settings.arrive = math.floor(value)
            Print("arrival radius: " .. settings.arrive .. " yd.")
        else
            Print("usage: /nt arrive 18  (5-60 yards)")
        end

    elseif command == "replan" then
        local value = tonumber(rest)
        if value and value >= 0 and value <= 500 then
            settings.replan = math.floor(value)
            Print(settings.replan > 0
                and ("re-planning every " .. settings.replan .. " yd of movement.")
                or "re-planning off.")
        else
            Print("usage: /nt replan 30  (0-500 yards, 0 = off)")
        end

    elseif command == "ring" then
        local value = tonumber(rest)
        if value and value >= 0 and value <= 500 then
            settings.ring = math.floor(value)
            Print(settings.ring > 0
                and ("node markers become rings within " .. settings.ring .. " yd.")
                or "ring markers off.")
        else
            Print("usage: /nt ring 100  (0-500 yards, 0 = off)")
        end

    elseif command == "allnodes" then
        local value = OnOff(rest:lower())
        if value == nil then
            Print("usage: /nt allnodes on|off")
        else
            settings.allNodes = value
            if state.route then
                NodeTaxi:Redraw()
            end
            Print("all node icons " .. (value and "on" or "off") .. ".")
        end

    elseif command == "spur" then
        local value = tonumber(rest)
        if not value or value < 0 then
            Print("usage: /nt spur <yards> (0 = no node detours)")
        else
            settings.spur = value
            if state.route then
                NodeTaxi:BuildRoute(false)
            end
            Print(string.format("node spur limit: %.0f yd.", value))
        end

    elseif command == "cluster" then
        local value = tonumber(rest)
        if not value or value < 1 then
            Print("usage: /nt cluster <nodes> (max nodes from one cluster)")
        else
            settings.cluster = math.floor(value)
            if state.route then
                NodeTaxi:BuildRoute(false)
            end
            Print(string.format("cluster limit: %.0f node(s).", settings.cluster))
        end

    elseif command == "auto" then
        local value = OnOff(rest:lower())
        if value == nil then
            Print("usage: /nt auto on|off")
        else
            settings.auto = value
            Print("auto routing " .. (value and "on" or "off") .. ".")
        end

    elseif command == "debug" then
        PrintDebug()

    elseif command == "kind" then
        local kind = rest:lower()
        if kind == "auto" or kind == "herb" or kind == "ore" or kind == "both" then
            settings.kind = kind
            NodeTaxi.activeTracking = NodeTaxi:DetectTracking()
            if state.route then
                NodeTaxi:BuildRoute(false)
            end
            Print(string.format("route kind: %s (using %s).", kind, NodeTaxi:GetEffectiveKind()))
        else
            Print("usage: /nt kind auto|herb|ore|both")
        end

    elseif command == "learn" then
        local kind, id = rest:match("^(%a+)%s+(%d+)$")
        kind = kind and kind:lower() or nil
        id = tonumber(id)
        if not (kind and id) or (kind ~= "herb" and kind ~= "ore") then
            Print("usage: /nt learn herb|ore <spellID>   (find the id with /nt watch)")
            return
        end

        local name = SpellName(id)
        if not name then
            Print("no spell name for id " .. id .. " (wrong id, or the spell is not cached yet).")
            return
        end

        db.learnedSpells[kind][name] = true
        if kind == "herb" then
            herbNames[name] = true
            oreNames[name] = nil
        else
            oreNames[name] = true
            herbNames[name] = nil
        end
        Print(string.format("learned %s spell '%s' (id %d).", kind, name, id))

    elseif command == "watch" then
        watchCasts = not watchCasts
        Print("cast logging " .. (watchCasts and "on" or "off") .. ".")

    elseif command == "clear" then
        if rest:lower() == "yes" then
            db.nodes = {}
            NodeTaxi.nodeRevision = (NodeTaxi.nodeRevision or 0) + 1
            NodeTaxi:ClearRoute(nil, true)
            Print("all learned/imported nodes deleted; the baked snapshot stays.")
        else
            Print("this deletes every learned node. type /nt clear yes to confirm.")
        end

    else
        Print("unknown command '" .. command .. "'. /nt for help.")
    end
end

--[[ Load -------------------------------------------------------------------]]
local function RegisterTomTom()
    local tomtom = _G.TomTom
    if not tomtom then
        Print("TomTom not found; NodeTaxi needs it for the arrow target.")
        return
    end

    if type(tomtom.RegisterCallback) == "function" then
        tomtom.RegisterCallback(ns, "ArrowTargetChanged", function(_, uid)
            NodeTaxi:OnArrowTargetChanged(uid)
        end)
    else
        Print("this TomTom has no callback API; NodeTaxi cannot see the arrow target.")
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(1.5, function()
            local uid = ReadArrowTarget()
            if uid then
                NodeTaxi:OnArrowTargetChanged(uid)
            end
        end)
    end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
driver:RegisterEvent("MINIMAP_UPDATE_TRACKING")

local elapsedSinceTick = 0
local elapsedSincePosition = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    if db then
        elapsedSincePosition = elapsedSincePosition + elapsed
        if elapsedSincePosition >= 0.5 then
            elapsedSincePosition = 0
            local map, x, y = NodeTaxi:GetPlayerZone()
            if map and x and y then
                NodeTaxi.lastPos = {
                    map = map,
                    x = x,
                    y = y,
                    t = GetTime(),
                    onTaxi = UnitOnTaxi and UnitOnTaxi("player") or false,
                }
            end
        end
    end

    if not state.route then
        return
    end

    elapsedSinceTick = elapsedSinceTick + elapsed
    if elapsedSinceTick >= 0.35 then
        elapsedSinceTick = 0
        NodeTaxi:Tick()
        if NodeTaxi.RedrawMinimap then
            NodeTaxi:RedrawMinimap()
        end
    end
end)

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InitDB()

        local version = AddonVersion()
        local _, build = GetBuildInfo()
        local mapID, px, py = NodeTaxi:GetPlayerZone()
        AddLog("session", {
            v = version,
            build = build,
            seed = NodeTaxi.SeedData and NodeTaxi.SeedData.version or "none",
            seedNodes = NodeTaxi:SeedCount(nil),
            map = mapID,
            x = px,
            y = py,
        })

        NodeTaxi.activeTracking = NodeTaxi:DetectTracking()
        NodeTaxi.lastPos = nil
        NodeTaxi:BackfillNodeIDs()

        local herb, ore = BuildGatherNames()
        if settings.debug then
            Print(string.format("gather spells: herb=%s ore=%s", tostring(herb), tostring(ore)))
        end

        RegisterTomTom()

        if settings.welcome then
            Print(string.format("loaded. %d node(s) known. /nt for commands.", NodeTaxi:NodeCount(nil)))
        end

        if NodeTaxi:NodeCount(nil) < 50 and #GetGatherMateSources() > 0 then
            Print("GatherMate2 data detected. /nt import gathermate2 to seed the routes.")
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if not db then
            return
        end

        NodeTaxi:RecordZoneTransition()
        NodeTaxi:OnTrackingChanged()

        local mapID = NodeTaxi:GetPlayerZone()
        if not mapID then
            return
        end

        if state.route and state.route.map ~= mapID then
            NodeTaxi:ClearRoute(nil, true)
        end

        local dest = state.dest
        if dest and not state.route and settings.auto then
            -- This also rebuilds the next zone leg after a border crossing.
            ScheduleBuild(1.0)
        end

        NodeTaxi:Redraw()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if db then
            OnSpellcastSucceeded(...)
        end

    elseif event == "MINIMAP_UPDATE_TRACKING" then
        if db then
            NodeTaxi:OnTrackingChanged()
        end
    end
end

driver:SetScript("OnEvent", OnEvent)

SLASH_NODETAXI1 = "/nodetaxi"
SLASH_NODETAXI2 = "/nt"
SlashCmdList["NODETAXI"] = HandleCommand

NodeTaxi.HandleCommand = HandleCommand
NodeTaxi.InitDB = InitDB
