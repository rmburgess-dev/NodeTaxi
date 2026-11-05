--[[--------------------------------------------------------------------------
    NodeTaxi - overlays
    --------------------------------------------------------------------------
    Draws the dashed "taxi" path on the world map and on the minimap, plus a
    diamond for every node that is still ahead of you. Everything here is a
    private frame/line/texture; no TomTom frame, pin or waypoint is touched.

    World map: a frame parented to the map canvas, so panning and zooming are
    handled by the client. Dashes are short Line regions.
    Minimap: normalised offsets from the minimap centre, using
    C_Minimap.GetViewRadius() and the rotate-minimap cvar.
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local NodeTaxi = ns
local Route = ns.Route

local sqrt, sin, cos, min, max, pi = math.sqrt, math.sin, math.cos, math.min, math.max, math.pi

local COLORS = {
    path = { 1.00, 0.82, 0.20, 0.92 },      -- taxi yellow
    pathFirst = { 1.00, 0.95, 0.65, 1.00 },
    preview = { 0.35, 0.90, 1.00, 0.95 },
    cross = { 0.40, 0.78, 1.00, 0.35 },
    crossPath = { 0.40, 0.78, 1.00, 0.65 },
    herb = { 0.30, 1.00, 0.45, 1.00 },
    ore = { 1.00, 0.62, 0.20, 1.00 },
    manual = { 0.90, 0.90, 0.95, 1.00 },
}

local worldFrame, worldLines, worldMarkers = nil, {}, {}
local minimapFrame, minimapLines, minimapMarkers = nil, {}, {}
local worldElapsed = 0

local function GetMapRect(mapID, topMapID)
    if not (C_Map and C_Map.GetMapRectOnMap) then
        return nil
    end
    local ok, left, right, bottom, top = pcall(C_Map.GetMapRectOnMap, mapID, topMapID)
    if ok then
        return left, right, bottom, top
    end
    return nil
end

local function GetMapInfo(mapID)
    if not (C_Map and C_Map.GetMapInfo) then
        return nil
    end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok then
        return info
    end
    return nil
end

local function GetCanvas()
    local worldMap = _G.WorldMapFrame
    if not worldMap then
        return nil, nil
    end

    local scroll = worldMap.ScrollContainer
    if scroll and scroll.Child then
        return scroll.Child, "ScrollContainer.Child"
    end

    if worldMap.GetCanvasContainer then
        local ok, canvas = pcall(worldMap.GetCanvasContainer, worldMap)
        if ok and canvas then
            return canvas, "GetCanvasContainer()"
        end
    end

    return nil, nil
end

local function NewLine(pool, parent, mask)
    for i = 1, #pool do
        local line = pool[i]
        if not line:IsShown() then
            line:Show()
            return line
        end
    end

    local line = parent:CreateLine(nil, "OVERLAY")
    if line.SetTexture then
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    if mask and line.AddMaskTexture then
        pcall(line.AddMaskTexture, line, mask)
    end
    pool[#pool + 1] = line
    return line
end

local function GetMinimapMask()
    if not (Minimap and Minimap.GetMaskTexture) then
        return nil
    end
    local ok, mask = pcall(Minimap.GetMaskTexture, Minimap)
    if ok then
        return mask
    end
    return nil
end

local function NewMarker(pool, parent)
    for i = 1, #pool do
        local marker = pool[i]
        if not marker:IsShown() then
            marker:Show()
            return marker
        end
    end

    local marker = parent:CreateTexture(nil, "OVERLAY")
    marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    pool[#pool + 1] = marker
    return marker
end

local function HidePool(pool)
    for i = 1, #pool do
        pool[i]:Hide()
    end
end

-- Short dashes between two points. Coordinates are relative to the parent's
-- TOPLEFT corner, with y growing downwards (UI convention).
local function DrawDashes(pool, parent, x1, y1, x2, y2, dash, gap, thickness, color)
    local dx, dy = x2 - x1, y2 - y1
    local length = sqrt(dx * dx + dy * dy)
    if length < 1 then
        return
    end

    local ux, uy = dx / length, dy / length
    local step = dash + gap
    local position = 0
    local r, g, b, a = color[1], color[2], color[3], color[4]

    while position < length do
        local segment = min(dash, length - position)
        if segment > 0.6 then
            local ax, ay = x1 + ux * position, y1 + uy * position
            local bx, by = x1 + ux * (position + segment), y1 + uy * (position + segment)

            local line = NewLine(pool, parent)
            line:SetThickness(thickness)
            line:SetVertexColor(r, g, b, a)
            line:SetStartPoint("TOPLEFT", parent, ax, -ay)
            line:SetEndPoint("TOPLEFT", parent, bx, -by)
        end

        position = position + step
    end
end

local function NodeColor(kind)
    return COLORS[kind] or COLORS.manual
end

local iconCache = {}

local function SpellTexture(spellID)
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

-- Generic node icons. The spell textures come from the client so they exist
-- on this build; the hard-coded paths are fallbacks for older clients.
local function NodeIcon(node)
    local kind = type(node) == "table" and node.kind or node
    local nodeID = type(node) == "table" and node.nodeID or nil

    if nodeID and NodeTaxi.SeedData and NodeTaxi.SeedData.icons then
        local specific = NodeTaxi.SeedData.icons[nodeID]
        if specific then
            return specific
        end
    end

    local cached = iconCache[kind]
    if cached then
        return cached
    end

    local texture
    if kind == "herb" then
        texture = SpellTexture(2366) or "Interface\\Icons\\INV_Misc_Herb_07"
    elseif kind == "ore" then
        texture = SpellTexture(2575) or "Interface\\Icons\\INV_Ore_Copper_01"
    else
        texture = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    iconCache[kind] = texture
    return texture
end
NodeTaxi.NodeIcon = NodeIcon

-- Hollow rings mark the expected node position once you are close. Leaving
-- the centre empty is the point: the game's own tracking dot/minimap icon can
-- be seen inside the ring, so you can tell whether a node is really there.
local function DrawWorldRing(pool, parent, x, y, radius, color, thickness)
    local segments = 12
    for i = 0, segments - 1 do
        local a1 = (i + 0.15) * 2 * pi / segments
        local a2 = (i + 0.85) * 2 * pi / segments

        local line = NewLine(pool, parent)
        line:SetThickness(thickness)
        line:SetVertexColor(color[1], color[2], color[3], color[4])
        line:SetStartPoint("TOPLEFT", parent, x + cos(a1) * radius, -(y + sin(a1) * radius))
        line:SetEndPoint("TOPLEFT", parent, x + cos(a2) * radius, -(y + sin(a2) * radius))
    end
end

local function DrawMinimapRing(pool, parent, x, y, radius, color, thickness, mask)
    local segments = 12
    for i = 0, segments - 1 do
        local a1 = (i + 0.15) * 2 * pi / segments
        local a2 = (i + 0.85) * 2 * pi / segments

        local line = NewLine(pool, parent, mask)
        line:SetThickness(thickness)
        line:SetVertexColor(color[1], color[2], color[3], color[4])
        line:SetStartPoint("CENTER", Minimap, x + cos(a1) * radius, y + sin(a1) * radius)
        line:SetEndPoint("CENTER", Minimap, x + cos(a2) * radius, y + sin(a2) * radius)
    end
end

local function DrawWorldIcon(pool, parent, x, y, size, texture, alpha)
    local marker = NewMarker(pool, parent)
    marker:SetTexture(texture)
    marker:SetSize(size, size)
    marker:SetVertexColor(1, 1, 1, alpha or 1)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
    if marker.SetRotation then
        marker:SetRotation(0)
    end
end

local function DrawMinimapIcon(pool, parent, x, y, size, texture, alpha)
    local marker = NewMarker(pool, parent)
    marker:SetTexture(texture)
    marker:SetSize(size, size)
    marker:SetVertexColor(1, 1, 1, alpha or 1)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", Minimap, x, y)
    if marker.SetRotation then
        marker:SetRotation(0)
    end
end

--[[ World map -------------------------------------------------------------]]
local worldMapHooksInstalled = false

local function InstallWorldMapHooks()
    if worldMapHooksInstalled then
        return
    end

    local worldMap = _G.WorldMapFrame
    if not worldMap then
        return
    end
    worldMapHooksInstalled = true

    worldMap:HookScript("OnShow", function()
        NodeTaxi:RedrawWorld()
    end)

    if type(worldMap.OnCanvasScaleChanged) == "function" then
        hooksecurefunc(worldMap, "OnCanvasScaleChanged", function()
            NodeTaxi:RedrawWorld()
        end)
    end

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("MapCanvas.MapSet", function()
            NodeTaxi:RedrawWorld()
        end, NodeTaxi)
    end
end

function NodeTaxi:EnsureWorldOverlay()
    if worldFrame then
        return worldFrame
    end

    local canvas, source = GetCanvas()
    if not canvas then
        return nil
    end

    local frame = CreateFrame("Frame", "NodeTaxiWorldOverlay", canvas)
    frame:SetAllPoints(canvas)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(canvas:GetFrameLevel() + 5)
    worldFrame = frame
    self.worldOverlaySource = source

    InstallWorldMapHooks()

    frame:SetScript("OnUpdate", function(_, elapsed)
        worldElapsed = worldElapsed + elapsed
        if worldElapsed < 0.5 then
            return
        end
        worldElapsed = 0

        if NodeTaxi.state.route and _G.WorldMapFrame and _G.WorldMapFrame:IsShown() then
            NodeTaxi:RedrawWorld()
        end
    end)

    return frame
end

function NodeTaxi:ClearWorldOverlay()
    HidePool(worldLines)
    HidePool(worldMarkers)
end

-- Map coordinates are top-down: y = 0 is the north edge, y = 1 the south
-- edge (the same convention C_Map/HBD and RareScanner use). The canvas draws
-- from TOPLEFT with a negative y offset, so the canvas y is simply y*height.
function NodeTaxi:MapPointToCanvas(mapID, x, y, topMapID, width, height)
    local tx, ty = Route.MapPointTo(mapID, x, y, topMapID, GetMapRect, GetMapInfo)
    if not tx or not ty then
        return nil
    end
    return tx * width, ty * height
end

function NodeTaxi:RedrawWorld()
    local frame = self:EnsureWorldOverlay()
    if not frame then
        return
    end

    HidePool(worldLines)
    HidePool(worldMarkers)

    local route = self.state.route
    local worldMap = _G.WorldMapFrame
    if not route or not worldMap or not worldMap:IsShown() then
        return
    end

    local topMapID = worldMap:GetMapID()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    if not topMapID or not width or width < 2 or not height or height < 2 then
        return
    end

    local function ToScreen(mapID, x, y)
        return NodeTaxi:MapPointToCanvas(mapID, x, y, topMapID, width, height)
    end

    local points = {}

    local playerMap, px, py = self:GetPlayerZone()
    if playerMap and px then
        local sx, sy = ToScreen(playerMap, px, py)
        if sx then
            points[#points + 1] = { x = sx, y = sy, live = true }
        end
    end

    local firstIndex = route.index or 1
    for i = firstIndex, #route.nodes do
        local node = route.nodes[i]
        local nx, ny = ToScreen(node.map or route.map, node.x, node.y)
        if nx then
            points[#points + 1] = { x = nx, y = ny, node = node, index = i }
        end
    end

    if route.dest then
        local dx, dy = ToScreen(route.dest.map, route.dest.x, route.dest.y)
        if dx then
            points[#points + 1] = { x = dx, y = dy, dest = true }
        end
    end

    -- Faint continuation through the following zones. When a full leg plan
    -- exists we draw its nodes and path below; otherwise fall back to the
    -- transition line only.
    if route.crossPath and not route.preview and (not route.legs or #route.legs <= 1) then
        local previous
        for i = 2, #route.crossPath do
            local point = route.crossPath[i]
            local sx, sy = ToScreen(point.map, point.x, point.y)
            if sx and previous then
                DrawDashes(worldLines, frame, previous.x, previous.y, sx, sy, 6, 8, 1.5, COLORS.cross)
            end
            previous = sx and { x = sx, y = sy } or nil
        end
    end

    -- Future legs: their selected nodes and dashed path across each zone.
    if route.legs and #route.legs > 1 then
        local previousExit
        if route.dest then
            local ex, ey = ToScreen(route.dest.map, route.dest.x, route.dest.y)
            if ex then
                previousExit = { x = ex, y = ey }
            end
        end

        for i = 2, #route.legs do
            local leg = route.legs[i]
            local startX, startY = ToScreen(leg.map, leg.startX, leg.startY)
            if startX and previousExit then
                DrawDashes(worldLines, frame, previousExit.x, previousExit.y,
                    startX, startY, 6, 8, 1.5, COLORS.cross)
            end

            local legPoints = {}
            if startX then
                legPoints[#legPoints + 1] = { x = startX, y = startY }
            end

            for _, node in ipairs(leg.nodes or {}) do
                local nx, ny = ToScreen(leg.map, node.x, node.y)
                if nx then
                    legPoints[#legPoints + 1] = { x = nx, y = ny }
                    DrawWorldIcon(worldMarkers, frame, nx, ny, 10, NodeIcon(node), 0.85)
                end
            end

            local endX, endY = ToScreen(leg.map, leg.destX, leg.destY)
            if endX then
                legPoints[#legPoints + 1] = { x = endX, y = endY }
            end

            for j = 2, #legPoints do
                local a, b = legPoints[j - 1], legPoints[j]
                DrawDashes(worldLines, frame, a.x, a.y, b.x, b.y, 6, 8, 1.5, COLORS.crossPath)
            end

            previousExit = endX and { x = endX, y = endY } or nil
        end
    end

    local pathColor = route.preview and COLORS.preview or COLORS.path
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local color = pathColor
        local thickness = 2
        if i == 2 and a.live then
            color = route.preview and COLORS.preview or COLORS.pathFirst
            thickness = 2.5
        end
        DrawDashes(worldLines, frame, a.x, a.y, b.x, b.y, 9, 7, thickness, color)
    end

    local ringDistance = (self.settings and self.settings.ring) or 0
    local pulse = 0.65 + 0.35 * sin(GetTime() * 4)

    for _, point in ipairs(points) do
        if point.node then
            local color = NodeColor(point.node.kind)
            local isNext = point.index == firstIndex
            if isNext then
                color = { color[1], color[2], color[3], pulse }
            end

            local close = false
            if ringDistance > 0 and playerMap and px then
                local distance = self:DistanceOnMap(playerMap, px, py, point.node.x, point.node.y)
                close = distance and distance <= ringDistance
            end

            if close then
                DrawWorldRing(worldLines, frame, point.x, point.y, isNext and 11 or 8, color, isNext and 2 or 1.5)
            else
                DrawWorldIcon(worldMarkers, frame, point.x, point.y,
                    isNext and 15 or 11, NodeIcon(point.node), isNext and pulse or 1)
            end
        end
    end
end

--[[ Minimap ---------------------------------------------------------------]]
function NodeTaxi:EnsureMinimapOverlay()
    if minimapFrame then
        return minimapFrame
    end
    if not Minimap then
        return nil
    end

    local frame = CreateFrame("Frame", "NodeTaxiMinimapOverlay", Minimap)
    frame:SetAllPoints(Minimap)
    frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    minimapFrame = frame
    return frame
end

function NodeTaxi:ClearMinimapOverlay()
    HidePool(minimapLines)
    HidePool(minimapMarkers)
end

function NodeTaxi:RedrawMinimap()
    local frame = self:EnsureMinimapOverlay()
    if not frame then
        return
    end

    HidePool(minimapLines)
    HidePool(minimapMarkers)

    local route = self.state.route
    if not route or not Minimap or not Minimap:IsShown() then
        return
    end
    if IsInInstance and IsInInstance() then
        return
    end

    local hbd = self:GetHBD()
    if not (hbd and hbd.GetPlayerWorldPosition) then
        return
    end

    local playerMap = self:GetPlayerZone()
    if not playerMap or playerMap ~= route.map then
        return
    end

    if not (C_Minimap and C_Minimap.GetViewRadius) then
        return
    end
    local radius = C_Minimap.GetViewRadius()
    if not radius or radius <= 0 then
        return
    end

    local ok, playerX, playerY, playerInstance = pcall(hbd.GetPlayerWorldPosition, hbd)
    if not ok or not playerX then
        return
    end

    local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    if halfWidth <= 0 then
        return
    end

    local rotate = GetCVar("rotateMinimap") == "1"
    local sinFacing, cosFacing
    if rotate then
        local facing = GetPlayerFacing()
        if facing then
            sinFacing, cosFacing = sin(facing), cos(facing)
        end
    end

    local function ToMinimap(worldX, worldY)
        local dx, dy = playerX - worldX, playerY - worldY
        if sinFacing and cosFacing then
            dx, dy = dx * cosFacing - dy * sinFacing, dx * sinFacing + dy * cosFacing
        end
        return (dx / radius) * halfWidth, -(dy / radius) * halfHeight
    end

    local points = { { x = 0, y = 0, live = true } }

    for i = route.index or 1, #route.nodes do
        local node = route.nodes[i]
        if (node.map or route.map) == route.map then
            local worldOk, wx, wy, instance = pcall(hbd.GetWorldCoordinatesFromZone, hbd, node.x, node.y, node.map or route.map)
            if worldOk and wx and instance == playerInstance then
                local u, v = ToMinimap(wx, wy)
                local dx, dy = playerX - wx, playerY - wy
                points[#points + 1] = {
                    x = u,
                    y = v,
                    node = node,
                    index = i,
                    distance = sqrt(dx * dx + dy * dy),
                }
            end
        end
    end

    if route.dest and route.dest.map == route.map then
        local worldOk, wx, wy, instance = pcall(hbd.GetWorldCoordinatesFromZone, hbd, route.dest.x, route.dest.y, route.dest.map)
        if worldOk and wx and instance == playerInstance then
            local u, v = ToMinimap(wx, wy)
            points[#points + 1] = { x = u, y = v, dest = true }
        end
    end

    local lineSet = minimapLines
    local parent = frame
    local mask = GetMinimapMask()
    local maxRadius = min(halfWidth, halfHeight) * 1.02
    local pathColor = route.preview and COLORS.preview or COLORS.path

    local function Inside(x, y)
        return (x * x + y * y) <= maxRadius * maxRadius
    end

    local function DrawMinimapDashes(x1, y1, x2, y2, color)
        local dx, dy = x2 - x1, y2 - y1
        local length = sqrt(dx * dx + dy * dy)
        if length < 1 then
            return
        end

        local ux, uy = dx / length, dy / length
        local position = 0
        while position < length do
            local segment = min(5, length - position)
            local ax, ay = x1 + ux * position, y1 + uy * position
            local bx, by = x1 + ux * (position + segment), y1 + uy * (position + segment)
            if Inside((ax + bx) / 2, (ay + by) / 2) then
                local line = NewLine(lineSet, parent, mask)
                line:SetThickness(2)
                line:SetVertexColor(color[1], color[2], color[3], color[4])
                line:SetStartPoint("CENTER", Minimap, ax, ay)
                line:SetEndPoint("CENTER", Minimap, bx, by)
            end
            position = position + 9
        end
    end

    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local color = pathColor
        if i == 2 and a.live then
            color = route.preview and COLORS.preview or COLORS.pathFirst
        end
        DrawMinimapDashes(a.x, a.y, b.x, b.y, color)
    end

    local ringDistance = (self.settings and self.settings.ring) or 0
    local pulse = 0.65 + 0.35 * sin(GetTime() * 4)

    for _, point in ipairs(points) do
        if point.node and Inside(point.x, point.y) then
            local color = NodeColor(point.node.kind)
            local isNext = point.index == (route.index or 1)
            if isNext then
                color = { color[1], color[2], color[3], pulse }
            end

            if ringDistance > 0 and point.distance and point.distance <= ringDistance then
                DrawMinimapRing(minimapLines, parent, point.x, point.y, isNext and 9 or 7, color, isNext and 2 or 1.5, mask)
            else
                DrawMinimapIcon(minimapMarkers, parent, point.x, point.y,
                    isNext and 13 or 9, NodeIcon(point.node), isNext and pulse or 1)
            end
        end
    end
end

--[[ Diagnostics -----------------------------------------------------------]]
function NodeTaxi:OverlayDebugInfo()
    return {
        world = worldFrame and ("ready via " .. tostring(self.worldOverlaySource)) or "not created",
        minimap = minimapFrame and "ready" or "not created",
    }
end

InstallWorldMapHooks()

-- A hidden frame keeps the world-map redraw alive even when the overlay has
-- not been created yet (for example: route built while the map is closed).
local watcher = CreateFrame("Frame")
local ok = pcall(watcher.RegisterEvent, watcher, "WORLD_MAP_UPDATE")
if ok then
    watcher:SetScript("OnEvent", function()
        NodeTaxi:RedrawWorld()
    end)
end
