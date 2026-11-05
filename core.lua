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
}

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
    db.version = 2

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

    db.nodes = db.nodes or {}
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
    elseif event == "route" then
        return string.format("%s route %d node(s) len=%.0f direct=%.0f target=%s",
            clock, entry.nodes or 0, entry.len or 0, entry.direct or 0,
            CoordText(entry.tx, entry.ty))
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

    if playerMap ~= dest.map then
        self:ClearRoute(nil, true)
        if announce then
            Print(string.format(
                "the arrow target is in %s, you are in %s. NodeTaxi plans inside one zone for now.",
                MapName(dest.map) or ("map " .. dest.map),
                MapName(playerMap) or ("map " .. playerMap)))
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

    local nodes = self:NodeListForMap(playerMap)
    local plan, err = Route.Plan({
        start = { x = px, y = py },
        dest = { x = dest.x, y = dest.y },
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

    if #plan.nodes == 0 then
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

    state.route = {
        map = playerMap,
        nodes = plan.nodes,
        dest = { map = dest.map, x = dest.x, y = dest.y, title = dest.title },
        index = 1,
        plan = plan,
        preview = false,
        planX = px,
        planY = py,
        planAt = GetTime(),
    }
    state.index = 1

    AddLog("route", {
        map = playerMap,
        x = px,
        y = py,
        tx = dest.x,
        ty = dest.y,
        nodes = #plan.nodes,
        len = plan.length,
        direct = plan.direct,
    })

    self:Redraw()

    if announce then
        local extra = plan.length - plan.direct
        local percent = plan.direct > 0 and (extra / plan.direct * 100) or 0
        Print(string.format(
            "%d node%s on the way to %s in %s: %.0f yd (direct %.0f, +%.0f%%)",
            plan.nodes and #plan.nodes or 0,
            (plan.nodes and #plan.nodes == 1) and "" or "s",
            CoordText(dest.x, dest.y),
            MapName(dest.map) or ("map " .. dest.map),
            plan.length, plan.direct, percent))
    end

    return true
end

-- Re-evaluate the remaining route from where the player is now. Completed
-- nodes (those before route.index) are not fed back in, so the new order
-- cannot send you back to something you already collected.
function NodeTaxi:ReplanFromCurrent(announce)
    local route = state.route
    if not route or route.preview then
        return false
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
    Print("  /nt kind auto|herb|ore|both  node filter; auto follows your tracking")
    Print("  /nt debug          diagnostic information")
    Print("  /nt learn herb|ore <spellID>  teach a gather spell by hand")
    Print("  /nt watch          log successful casts (to verify node learning)")
    Print("  /nt clear yes      delete every learned node")
end

local function PrintStatus()
    InitSettingsIfNeeded()
    local playerMap = NodeTaxi:GetPlayerZone()
    Print(string.format("settings: corridor %.0f yd, max %.0f nodes, detour %.1fx, arrive %.0f yd, auto %s, kind %s, replan %.0f yd, ring %.0f yd",
        settings.corridor, settings.maxNodes, settings.detour, settings.arrive,
        settings.auto and "on" or "off", settings.kind, settings.replan, settings.ring))
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
        Print(string.format("route: %d node(s), %d remaining, drawn on map/minimap",
            #route.nodes, math.max(0, #route.nodes - route.index + 1)))
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
driver:SetScript("OnUpdate", function(_, elapsed)
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

        NodeTaxi:OnTrackingChanged()

        local mapID = NodeTaxi:GetPlayerZone()
        if not mapID then
            return
        end

        if state.route and state.route.map ~= mapID then
            NodeTaxi:ClearRoute(nil, true)
        end

        local dest = state.dest
        if dest and dest.map == mapID and not state.route and settings.auto then
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
