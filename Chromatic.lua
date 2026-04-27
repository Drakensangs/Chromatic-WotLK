-- Chromatic for WoW 3.3.5a (Wrath of the Lich King)
-- Damage-type coloring, item rarity border coloring, and class-name coloring on tooltips.

-- ============================================================
-- § 0  Localized globals & shared utilities
-- ============================================================

local GetItemInfo                  = GetItemInfo
local GetContainerItemLink         = GetContainerItemLink
local GetInventoryItemLink         = GetInventoryItemLink
local GetMerchantItemLink          = GetMerchantItemLink
local GetLootSlotLink              = GetLootSlotLink
local GetQuestItemLink             = GetQuestItemLink
local GetQuestLogItemLink          = GetQuestLogItemLink
local GetAuctionItemLink           = GetAuctionItemLink
local GetTradeSkillItemLink        = GetTradeSkillItemLink
local GetTradeSkillReagentItemLink = GetTradeSkillReagentItemLink
local GetInboxItemLink             = GetInboxItemLink
local GetTradePlayerItemLink       = GetTradePlayerItemLink
local GetTradeTargetItemLink       = GetTradeTargetItemLink
local GetItemQualityColor          = GetItemQualityColor
local GetMouseFocus                = GetMouseFocus
local IsAddOnLoaded                = IsAddOnLoaded
local hooksecurefunc               = hooksecurefunc

local strfind  = string.find
local strgsub  = string.gsub
local strlower = string.lower
local strmatch = string.match
local floor    = math.floor
local tonumber = tonumber
local pairs    = pairs
local ipairs   = ipairs

local origCreateFrame = CreateFrame

-- ============================================================
-- § 1  Damage-type colorization
-- ============================================================

local cfgBorders      = true
local cfgClassColor   = true
local cfgElementColor = true

-- Result cache for ProcessDamageLine — declared here so RefreshConfig can wipe it.
local lineResultCache     = {}
local lineResultCacheSize = 0
local LINE_CACHE_MAX      = 512

local function RefreshConfig()
    local cfg       = ChromaticConfig
    cfgBorders      = cfg.borders
    cfgClassColor   = cfg.classcolor
    cfgElementColor = cfg.elementcolor
    -- Wipe the line result cache: toggling element color changes what
    -- ProcessDamageLine returns for every previously cached input.
    lineResultCache     = {}
    lineResultCacheSize = 0
end

-- ITEM_ELEMENT_SKIP and EXCEPTIONS are defined in Exceptions.lua and loaded into
-- ChromaticData before this file runs.
local ITEM_ELEMENT_SKIP = ChromaticData.ITEM_ELEMENT_SKIP

local DAMAGE_COLORS = {
    ["Arcane"] = "|cFFFF66FF",
    ["Fire"]   = "|cFFFF0000",
    ["Frost"]  = "|cFF00FFFF",
    ["Holy"]   = "|cFFFFFF00",
    ["Nature"] = "|cFF00FF00",
    ["Shadow"] = "|cFF9900FF",
}

local EXCEPTIONS    = ChromaticData.EXCEPTIONS
local numExceptions = #EXCEPTIONS

local PLACEHOLDERS = {}
for i = 1, numExceptions do
    PLACEHOLDERS[i] = "\001P" .. i .. "\001"
end

local PASS              = {}
local DTYPE_NAME        = {}
local DTYPE_NAME_LOWER  = {}
local STANDALONE_PREFIX = {}
local SPACE_PREFIX      = {}

do
    local ORDER = { "Arcane", "Fire", "Frost", "Holy", "Nature", "Shadow" }
    for n, dt in ipairs(ORDER) do
        local color = DAMAGE_COLORS[dt]
        local dtl = strlower(dt)
        local cr  = color .. dt  .. " Resistance|r"
        local csd = color .. dt  .. " Spell Damage|r"
        local cd  = color .. dt  .. " Damage|r"
        local cs  = color .. dt  .. "|r"
        local csl = color .. dtl .. "|r"

        PASS[n] = {
            -- Resistance title case (1-8)
            "([^%a])" .. dt .. " Resistance([^%a])", "%1" .. cr  .. "%2",
            "^"       .. dt .. " Resistance([^%a])",        cr  .. "%1",
            "([^%a])" .. dt .. " Resistance$",       "%1" .. cr,
            "^"       .. dt .. " Resistance$",               cr,
            -- Spell Damage (9-16)
            "([^%a])" .. dt .. " Spell Damage([^%a])", "%1" .. csd .. "%2",
            "^"       .. dt .. " Spell Damage([^%a])",        csd .. "%1",
            "([^%a])" .. dt .. " Spell Damage$",       "%1" .. csd,
            "^"       .. dt .. " Spell Damage$",               csd,
            -- Damage title case (17-24)
            "([^%a])" .. dt .. " Damage([^%a])", "%1" .. cd .. "%2",
            "^"       .. dt .. " Damage([^%a])",        cd .. "%1",
            "([^%a])" .. dt .. " Damage$",       "%1" .. cd,
            "^"       .. dt .. " Damage$",               cd,
            -- Damage lower case (25-32)
            "([^%a])" .. dt .. " damage([^%a])", "%1" .. cs .. " damage%2",
            "^"       .. dt .. " damage([^%a])",        cs .. " damage%1",
            "([^%a])" .. dt .. " damage$",       "%1" .. cs .. " damage",
            "^"       .. dt .. " damage$",               cs .. " damage",
            -- Standalone title case (33-40)
            "([^%a])" .. dt .. "([^%a])", "%1" .. cs .. "%2",
            "^"       .. dt .. "([^%a])",        cs .. "%1",
            "([^%a])" .. dt .. "$",       "%1" .. cs,
            "^"       .. dt .. "$",               cs,
            -- Resistance lower case (41-48)
            "([^%a])" .. dtl .. " resistance([^%a])", "%1" .. csl .. " resistance%2",
            "^"       .. dtl .. " resistance([^%a])",        csl .. " resistance%1",
            "([^%a])" .. dtl .. " resistance$",       "%1" .. csl .. " resistance",
            "^"       .. dtl .. " resistance$",               csl .. " resistance",
            -- Standalone lower case (49-56)
            "([^%a])" .. dtl .. "([^%a])", "%1" .. csl .. "%2",
            "^"       .. dtl .. "([^%a])",        csl .. "%1",
            "([^%a])" .. dtl .. "$",       "%1" .. csl,
            "^"       .. dtl .. "$",               csl,
        }
        DTYPE_NAME[n]        = dt
        DTYPE_NAME_LOWER[n]  = dtl
        STANDALONE_PREFIX[n] = color .. dt
        SPACE_PREFIX[n]      = " " .. dt
    end
end
local numDamageTypes = 6

DAMAGE_COLORS = nil

-- Pre-allocated reuse table: avoids per-call allocation in ProcessDamageLine.
local protectedPhrases = {}
for i = 1, numExceptions do protectedPhrases[i] = false end

local function ProcessDamageLine(text)
    if not cfgElementColor then return text end

    local cached = lineResultCache[text]
    if cached ~= nil then return cached end

    -- Fast early-out: scan for any damage keyword before doing any real work.
    local anyFound = false
    for i = 1, numDamageTypes do
        if strfind(text, DTYPE_NAME[i], 1, true)
        or strfind(text, DTYPE_NAME_LOWER[i], 1, true) then
            anyFound = true
            break
        end
    end
    if not anyFound then
        if lineResultCacheSize >= LINE_CACHE_MAX then
            lineResultCache     = {}
            lineResultCacheSize = 0
        end
        lineResultCache[text] = text
        lineResultCacheSize   = lineResultCacheSize + 1
        return text
    end

    local newText = text

    -- Protect exception phrases with placeholders.
    local anyProtected = false
    for i = 1, numExceptions do
        if strfind(newText, EXCEPTIONS[i], 1, true) then
            newText = strgsub(newText, EXCEPTIONS[i], PLACEHOLDERS[i])
            protectedPhrases[i] = true
            anyProtected = true
        else
            protectedPhrases[i] = false
        end
    end

    for i = 1, numDamageTypes do
        local hasTitle = strfind(newText, DTYPE_NAME[i], 1, true)
        if hasTitle then
            local p = PASS[i]
            newText = strgsub(newText, p[1],  p[2])
            newText = strgsub(newText, p[3],  p[4])
            newText = strgsub(newText, p[5],  p[6])
            newText = strgsub(newText, p[7],  p[8])
            newText = strgsub(newText, p[9],  p[10])
            newText = strgsub(newText, p[11], p[12])
            newText = strgsub(newText, p[13], p[14])
            newText = strgsub(newText, p[15], p[16])
            newText = strgsub(newText, p[17], p[18])
            newText = strgsub(newText, p[19], p[20])
            newText = strgsub(newText, p[21], p[22])
            newText = strgsub(newText, p[23], p[24])
            newText = strgsub(newText, p[25], p[26])
            newText = strgsub(newText, p[27], p[28])
            newText = strgsub(newText, p[29], p[30])
            newText = strgsub(newText, p[31], p[32])
            if not strfind(newText, STANDALONE_PREFIX[i], 1, true)
            or strfind(newText, SPACE_PREFIX[i], 1, true) then
                newText = strgsub(newText, p[33], p[34])
                newText = strgsub(newText, p[35], p[36])
                newText = strgsub(newText, p[37], p[38])
                newText = strgsub(newText, p[39], p[40])
            end
        end
        if strfind(newText, DTYPE_NAME_LOWER[i], 1, true) then
            local p = PASS[i]
            newText = strgsub(newText, p[41], p[42])
            newText = strgsub(newText, p[43], p[44])
            newText = strgsub(newText, p[45], p[46])
            newText = strgsub(newText, p[47], p[48])
            newText = strgsub(newText, p[49], p[50])
            newText = strgsub(newText, p[51], p[52])
            newText = strgsub(newText, p[53], p[54])
            newText = strgsub(newText, p[55], p[56])
        end
    end

    if anyProtected then
        for i = 1, numExceptions do
            if protectedPhrases[i] then
                newText = strgsub(newText, PLACEHOLDERS[i], EXCEPTIONS[i])
            end
        end
    end

    if lineResultCacheSize >= LINE_CACHE_MAX then
        lineResultCache     = {}
        lineResultCacheSize = 0
    end
    lineResultCache[text] = newText
    lineResultCacheSize   = lineResultCacheSize + 1

    return newText
end

-- ============================================================
-- § 2  Class-name colorization
-- ============================================================

local CLASS_NAMES = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
    "Shaman",  "Mage",    "Warlock", "Druid", "Death Knight",
}
local CLASS_REPLS = {
    "|cFFC79C6EWarrior|r",      "|cFFF58CBAPaladin|r",  "|cFFABD473Hunter|r",
    "|cFFFFF569Rogue|r",        "|cFFFFFFFFPriest|r",   "|cFF0070DEShaman|r",
    "|cFF69CCF0Mage|r",         "|cFF9482C9Warlock|r",  "|cFFFF7D0ADruid|r",
    "|cFFC41F3BDeath Knight|r",
}
local numClasses = #CLASS_NAMES

local classLineCache = {}

local function ProcessClassLine(text)
    local cached = classLineCache[text]
    if cached then return cached, true end

    local newText  = text
    local modified = false
    for i = 1, numClasses do
        if strfind(newText, CLASS_NAMES[i], 1, true) then
            newText  = strgsub(newText, CLASS_NAMES[i], CLASS_REPLS[i])
            modified = true
        end
    end

    if modified then
        classLineCache[text] = newText
    end
    return newText, modified
end

-- ============================================================
-- § 3  Combined tooltip line walker
-- ============================================================

local tooltipBaseLines    = {}  -- NumLines() snapshot before addon hooks add lines
local lineCache = {}

local function ProcessTooltipLines(tooltip, skipElement)
    if not cfgElementColor and not cfgClassColor then return end

    local numLines = tooltip:NumLines()
    if numLines == 0 then return end

    local cache = lineCache[tooltip]
    if not cache then
        local name = tooltip:GetName()
        if not name then return end
        cache = { left = {}, right = {}, max = 0, lp = name .. "TextLeft", rp = name .. "TextRight" }
        lineCache[tooltip] = cache
    end

    -- Extend the line-frame cache only when new lines have appeared.
    if numLines > cache.max then
        local lp = cache.lp
        local rp = cache.rp
        local G  = _G
        for i = cache.max + 1, numLines do
            cache.left[i]  = G[lp .. i]
            cache.right[i] = G[rp .. i]
        end
        cache.max = numLines
    end

    local left  = cache.left
    local right = cache.right

    if cfgClassColor then
        local line1 = left[1]
        if line1 and line1:GetFont() then
            local text = line1:GetText()
            if text and strfind(text, "Classes:", 1, true) then
                local newText, modified = ProcessClassLine(text)
                if modified then line1:SetText(newText) end
            end
        end
    end

    local doElem  = cfgElementColor and not skipElement
    local doClass = cfgClassColor
    local classLineDone = not doClass
    local baseLine  = tooltipBaseLines[tooltip] or numLines
    local inMobSkip = false
    for i = 2, numLines do
        local isAddonLine = i > baseLine
        local lineL = left[i]
        if lineL and lineL:GetFont() then
            local text = lineL:GetText()
            if text then
                if not isAddonLine and strfind(text, " Mobs:", 1, true) then
                    inMobSkip     = true
                    classLineDone = true  -- mob names are never class lines
                elseif isAddonLine or not inMobSkip then
                    local newText = doElem and ProcessDamageLine(text) or text
                    if not classLineDone and strfind(newText, "Classes:", 1, true) then
                        local newText2, classModified = ProcessClassLine(newText)
                        if classModified then
                            classLineDone = true
                            lineL:SetText(newText2)
                        elseif newText ~= text then
                            lineL:SetText(newText)
                        end
                    elseif newText ~= text then
                        lineL:SetText(newText)
                    end
                end
            end
        end
        if doElem and (isAddonLine or not inMobSkip) then
            local lineR = right[i]
            if lineR and lineR:GetFont() then
                local text = lineR:GetText()
                if text then
                    local newText = ProcessDamageLine(text)
                    if newText ~= text then lineR:SetText(newText) end
                end
            end
        end
    end
end

-- ============================================================
-- § 4  Rarity border coloring
-- ============================================================

local QC = {
    [0]=0.62, 0.62, 0.62,  -- 0 Poor
         1.00, 1.00, 1.00,  -- 1 Common
         0.12, 1.00, 0.00,  -- 2 Uncommon
         0.00, 0.44, 0.87,  -- 3 Rare
         0.64, 0.21, 0.93,  -- 4 Epic
         1.00, 0.50, 0.00,  -- 5 Legendary
         0.90, 0.80, 0.50,  -- 6 Artifact
         0.90, 0.80, 0.50,  -- 7 Heirloom
}

local ITEM_ID_PATTERN = "item:(%d+)"
local qualityCache    = {}

local function QualityFromLink(link)
    local idStr = strmatch(link, ITEM_ID_PATTERN)
    if not idStr then return nil end
    local cached = qualityCache[idStr]
    if cached ~= nil then return cached end
    local _, _, quality = GetItemInfo(link)
    if quality then qualityCache[idStr] = quality end
    return quality
end

local ApplyBorderColor  -- forward-declared; body assigned below

local RETRY_TIMEOUT = 5
local queue  = {}
local qHead  = 1
local qTail  = 0

local retryFrame = origCreateFrame("Frame")
retryFrame:Hide()
retryFrame:SetScript("OnUpdate", function(_, elapsed)
    local i       = qHead
    local anyLeft = false
    while i <= qTail do
        local slot = queue[i]
        if slot then
            slot.elapsed = slot.elapsed + elapsed
            local quality = QualityFromLink(slot.link)
            if quality then
                if slot.tooltip and slot.tooltip:IsVisible() then
                    ApplyBorderColor(slot.tooltip, quality)
                end
                queue[i] = nil
            elseif slot.elapsed >= RETRY_TIMEOUT then
                queue[i] = nil
            else
                anyLeft = true
            end
        end
        i = i + 1
    end
    if not anyLeft then
        qHead = 1
        qTail = 0
        retryFrame:Hide()
    else
        while qHead <= qTail and not queue[qHead] do
            qHead = qHead + 1
        end
    end
end)

local function EnqueueRetry(tooltip, link)
    qTail = qTail + 1
    local slot = queue[qTail]
    if slot then
        slot.tooltip = tooltip
        slot.link    = link
        slot.elapsed = 0
    else
        queue[qTail] = { tooltip = tooltip, link = link, elapsed = 0 }
    end
    retryFrame:Show()
end

local function CancelRetryForTooltip(tooltip)
    for i = qHead, qTail do
        local slot = queue[i]
        if slot and slot.tooltip == tooltip then
            slot.tooltip = nil
            slot.elapsed = RETRY_TIMEOUT
        end
    end
end

local tooltipActiveLink    = {}
local tooltipPendingRetry  = {}
local tooltipActiveQuality = {}

local function InstallBorderGuard(tooltip, quality)
    -- Install or update the border guard on this tooltip instance.
    -- The guard wraps SetBackdropBorderColor so any call that would reset the
    -- border to a non-rarity color is overridden with the rarity color instead.
    tooltipActiveQuality[tooltip] = quality
    if tooltip._chromatic_guardInstalled then return end
    tooltip._chromatic_guardInstalled = true
    local origSBBC = tooltip.SetBackdropBorderColor
    tooltip.SetBackdropBorderColor = function(self, r, g, b, a)
        local q = tooltipActiveQuality[self]
        if q ~= nil then
            local bq = q * 3
            origSBBC(self, QC[bq], QC[bq+1], QC[bq+2], 1)
        else
            origSBBC(self, r, g, b, a)
        end
    end
end

local function RemoveBorderGuard(tooltip)
    -- Temporarily disable the guard by clearing the active quality.
    -- The wrapper itself stays in place (it's cheap to keep and re-enabling it
    -- is just setting tooltipActiveQuality again).
    tooltipActiveQuality[tooltip] = nil
end

-- SetBorderColor wrapper inlined: the one-line function added overhead with no benefit.
ApplyBorderColor = function(tooltip, quality)
    tooltipActiveQuality[tooltip] = quality
    if not tooltip._chromatic_guardInstalled then
        InstallBorderGuard(tooltip, quality)
    end
    local b = quality * 3
    tooltip:SetBackdropBorderColor(QC[b], QC[b+1], QC[b+2], 1)
end

local function ResetBorderColor(tooltip)
    RemoveBorderGuard(tooltip)
    tooltip:SetBackdropBorderColor(1, 1, 1, 1)
end

local function rgbKey(r, g, b)
    return floor(r * 255 + 0.5) * 65536
         + floor(g * 255 + 0.5) * 256
         + floor(b * 255 + 0.5)
end

local rgbToQuality = {}
do
    -- GetItemQualityColor is always present in WotLK; no fallback needed.
    for q = 0, 7 do
        local r, g, b = GetItemQualityColor(q)
        if r then rgbToQuality[rgbKey(r, g, b)] = q end
    end
end

local function applyFromLineColor(frame, lineIndex)
    if not cfgBorders then return end
    if not tooltipActiveLink[frame] then
        local lineFrame
        local cache = lineCache[frame]
        if cache then lineFrame = cache.left[lineIndex] end
        if not lineFrame then
            lineFrame = _G[frame:GetName() .. "TextLeft" .. lineIndex]
        end
        if lineFrame then
            local r, g, b = lineFrame:GetTextColor()
            if r then
                local quality = rgbToQuality[rgbKey(r, g, b)]
                if quality ~= nil then ApplyBorderColor(frame, quality) end
            end
        end
    end
end

-- ============================================================
-- § 5  Tooltip hooking — combined
-- ============================================================

local ELEMENT_SKIP_STRINGS = {}
local ELEMENT_SKIP_COUNT   = 0
do
    for id in pairs(ITEM_ELEMENT_SKIP) do
        ELEMENT_SKIP_COUNT = ELEMENT_SKIP_COUNT + 1
        ELEMENT_SKIP_STRINGS[ELEMENT_SKIP_COUNT] = "item:" .. id .. ":"
    end
end
ITEM_ELEMENT_SKIP = nil

local function IsElementSkipLink(link)
    if not link then return false end
    for i = 1, ELEMENT_SKIP_COUNT do
        if strfind(link, ELEMENT_SKIP_STRINGS[i], 1, true) then return true end
    end
    return false
end

local hookedTooltips = {}

local function WrapSetInventoryItem(tooltip)
    if not tooltip or not tooltip.SetInventoryItem then return end
    local orig = tooltip.SetInventoryItem
    tooltip.SetInventoryItem = function(self, unit, slot)
        local hasItem, hasCooldown, repairCost = orig(self, unit, slot)
        tooltipActiveLink[self] = nil
        -- Border handled by OnTooltipSetItem.
        if cfgBorders and not hasItem then ResetBorderColor(self) end
        local link = GetInventoryItemLink(unit, slot)
        ProcessTooltipLines(self, IsElementSkipLink(link))
        return hasItem, hasCooldown, repairCost
    end
end

local function HookTooltip(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end
    if not tooltip.SetHyperlink then return end
    hookedTooltips[tooltip] = true

    -- SetHyperlink: raw replacement to capture the link for tooltipActiveLink
    -- and ProcessTooltipLines before the engine populates the tooltip.
    -- pcall removed: it added overhead on every hover with no practical benefit
    -- (an error from origSHL would be a Blizzard bug we should not silently eat).
    local origSHL = tooltip.SetHyperlink
    tooltip.SetHyperlink = function(self, link)
        origSHL(self, link)
        tooltipBaseLines[self] = self:NumLines()
        if link and strfind(link, "item:", 1, true) then
            tooltipActiveLink[self] = link
        else
            tooltipActiveLink[self] = nil
            if cfgBorders then ResetBorderColor(self) end
        end
        ProcessTooltipLines(self, IsElementSkipLink(link))
    end

    -- OnTooltipSetItem: fires whenever the engine sets an item on this tooltip,
    -- covering every possible Set* path without enumerating them individually.
    -- Uses qualityCache to avoid redundant GetItemInfo calls.
    if tooltip.HookScript and tooltip:HasScript("OnTooltipSetItem") then
        tooltip:HookScript("OnTooltipSetItem", function(self)
            if not cfgBorders then return end
            local _, link = self:GetItem()
            if link then
                local quality = QualityFromLink(link)
                if quality then
                    ApplyBorderColor(self, quality)
                    tooltipPendingRetry[self] = nil
                else
                    EnqueueRetry(self, link)
                    tooltipPendingRetry[self] = true
                end
            end
        end)
    end

    WrapSetInventoryItem(tooltip)

    local origHide = tooltip:GetScript("OnHide")
    if origHide then
        tooltip:SetScript("OnHide", function(self)
            CancelRetryForTooltip(self)
            tooltipActiveLink[self]   = nil
            tooltipPendingRetry[self] = nil
            tooltipBaseLines[self]    = nil
            if cfgBorders then ResetBorderColor(self) end
            origHide(self)
        end)
    else
        tooltip:SetScript("OnHide", function(self)
            CancelRetryForTooltip(self)
            tooltipActiveLink[self]   = nil
            tooltipPendingRetry[self] = nil
            tooltipBaseLines[self]    = nil
            if cfgBorders then ResetBorderColor(self) end
        end)
    end
end

local function HookAddonTooltipMethods(tooltip)
    if not tooltip then return end
    HookTooltip(tooltip)

    if tooltip.SetBagItem then
        local orig = tooltip.SetBagItem
        tooltip.SetBagItem = function(self, bag, slot)
            orig(self, bag, slot)
            tooltipActiveLink[self] = nil
            local link = GetContainerItemLink(bag, slot)
            ProcessTooltipLines(self, IsElementSkipLink(link))
        end
    end

    if tooltip.SetLootItem then
        local orig = tooltip.SetLootItem
        tooltip.SetLootItem = function(self, index)
            orig(self, index)
            tooltipActiveLink[self] = nil
            local link = GetLootSlotLink(index)
            ProcessTooltipLines(self, IsElementSkipLink(link))
        end
    end
end

-- ============================================================
-- § 6  GameTooltip — Blizzard Set* hooks
-- ============================================================

local GT = GameTooltip
HookTooltip(GT)

local tooltipIsUnit = {}

hooksecurefunc(GT, "SetUnit", function(self)
    tooltipIsUnit[self] = true
end)

local MogItRef
local MogItChecked

hooksecurefunc(GT, "Show", function(self)
    if GetMouseFocus() ~= WorldFrame then
        if not MogItChecked then
            MogItRef     = _G["MogIt"]
            MogItChecked = true
        end
        local link     = tooltipActiveLink[self]
        local skipElem = tooltipIsUnit[self]
            or (MogItRef and self[MogItRef])
            or IsElementSkipLink(link)
        tooltipIsUnit[self] = nil
        ProcessTooltipLines(self, skipElem)
        applyFromLineColor(self, 1)
    end
end)

hooksecurefunc(GT, "SetBagItem", function(self, bag, slot)
    local link = GetContainerItemLink(bag, slot)
    tooltipActiveLink[self] = link
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetMerchantItem", function(self, index)
    tooltipActiveLink[self] = nil
    local link = GetMerchantItemLink(index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetLootItem", function(self, index)
    tooltipActiveLink[self] = nil
    local link = GetLootSlotLink(index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetQuestItem", function(self, qtype, index)
    tooltipActiveLink[self] = nil
    local link = GetQuestItemLink(qtype, index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetQuestLogItem", function(self, qtype, index)
    tooltipActiveLink[self] = nil
    local link = GetQuestLogItemLink(qtype, index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetAuctionItem", function(self, atype, index)
    tooltipActiveLink[self] = nil
    local link = GetAuctionItemLink(atype, index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetAuctionSellItem", function(self)
    tooltipActiveLink[self] = nil
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self)
end)

if GT.SetBuybackItem then
    hooksecurefunc(GT, "SetBuybackItem", function(self)
        tooltipActiveLink[self] = nil
        tooltipBaseLines[self]  = self:NumLines()
        ProcessTooltipLines(self)
    end)
end

hooksecurefunc(GT, "SetTradeSkillItem", function(self, index, reagentIndex)
    tooltipActiveLink[self] = nil
    local link = reagentIndex
        and GetTradeSkillReagentItemLink(index, reagentIndex)
         or GetTradeSkillItemLink(index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetInboxItem", function(self, mailIndex, attachIndex)
    tooltipActiveLink[self] = nil
    local link = GetInboxItemLink(mailIndex, attachIndex)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

if GT.SetSendMailItem then
    hooksecurefunc(GT, "SetSendMailItem", function(self)
        tooltipActiveLink[self] = nil
        tooltipBaseLines[self]  = self:NumLines()
        ProcessTooltipLines(self)
    end)
end

hooksecurefunc(GT, "SetTradePlayerItem", function(self, index)
    tooltipActiveLink[self] = nil
    local link = GetTradePlayerItemLink(index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

hooksecurefunc(GT, "SetTradeTargetItem", function(self, index)
    tooltipActiveLink[self] = nil
    local link = GetTradeTargetItemLink(index)
    tooltipBaseLines[self]  = self:NumLines()
    ProcessTooltipLines(self, IsElementSkipLink(link))
end)

-- Spell/trainer/talent/shapeshift/pet/glyph hooks.
do
    local function PostHook(self)
        ProcessTooltipLines(self)
    end

    hooksecurefunc(GT, "SetSpell",          PostHook)
    hooksecurefunc(GT, "SetTrainerService", PostHook)
    hooksecurefunc(GT, "SetTalent",         PostHook)
    hooksecurefunc(GT, "SetShapeshift",     PostHook)
    hooksecurefunc(GT, "SetPetAction",      PostHook)
    hooksecurefunc(GT, "SetGlyph",          PostHook)
end

do
    local function AuraPostHook(self)
        ProcessTooltipLines(self)
    end
    hooksecurefunc(GT, "SetUnitAura",   AuraPostHook)
    hooksecurefunc(GT, "SetUnitBuff",   AuraPostHook)
    hooksecurefunc(GT, "SetUnitDebuff", AuraPostHook)
end

-- SetAction: no item link available; infer border quality from the name text color.
hooksecurefunc(GT, "SetAction", function(self)
    tooltipActiveLink[self] = nil
    ProcessTooltipLines(self)
    applyFromLineColor(self, 1)
end)

HookTooltip(ItemRefTooltip)
hooksecurefunc(ItemRefTooltip, "Show", function(self)
    local base = tooltipBaseLines[self]
    if base and self:NumLines() > base then
        ProcessTooltipLines(self, IsElementSkipLink(tooltipActiveLink[self]))
    end
end)

-- GameTooltip_SetDefaultAnchor: reset border when the tooltip repositions.
hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
    if cfgBorders then ResetBorderColor(tooltip) end
end)

-- ============================================================
-- § 7  Dynamic tooltip detection
-- ============================================================

-- Hook CreateFrame via hooksecurefunc to avoid tainting the global.
-- Overwriting CreateFrame directly causes Blizzard protected actions
-- (e.g. "Set Focus") to be blocked with a taint error.
hooksecurefunc("CreateFrame", function(frameType, name, parent, template)
    if frameType == "GameTooltip" then
        local frame = _G[name]
        if frame then HookTooltip(frame) end
    end
end)

local NUM_PET_RES_TYPES = NUM_PET_RESISTANCE_TYPES or 5

local function HookPetResistances()
    if not PetPaperDollFrame_SetResistances then return end
    hooksecurefunc("PetPaperDollFrame_SetResistances", function()
        if not cfgElementColor then return end
        for i = 1, NUM_PET_RES_TYPES do
            local frame = _G["PetMagicResFrame" .. i]
            if frame and frame.tooltip then
                frame.tooltip = ProcessDamageLine(frame.tooltip)
            end
        end
    end)
end

-- CharacterFrame resistances
local NUM_CHAR_RES_TYPES = NUM_RESISTANCE_TYPES or 5

local function HookCharacterResistances()
    if not PaperDollFrame_SetResistances then return end
    hooksecurefunc("PaperDollFrame_SetResistances", function()
        if not cfgElementColor then return end
        for i = 1, NUM_CHAR_RES_TYPES do
            local frame = _G["MagicResFrame" .. i]
            if frame and frame.tooltip then
                frame.tooltip = ProcessDamageLine(frame.tooltip)
            end
        end
    end)
end

-- AtlasLoot

local function HookAtlasLoot()
    HookAddonTooltipMethods(_G["AtlasLootTooltip"])
    HookAddonTooltipMethods(_G["AtlasLootTooltip1"])
    HookAddonTooltipMethods(_G["AtlasLootTooltip2"])
end

-- AtlasQuest

local function HookAtlasQuest()
    HookAddonTooltipMethods(_G["AtlasQuestTooltip"])
end

local function WrapShoppingShow(tt)
    if not tt or not tt.Show then return end
    local origST = tt.Show
    tt.Show = function(self)
        if cfgBorders then
            local link = tooltipActiveLink[self]
            if link then
                -- Standard path: link known, use cache.
                local quality = QualityFromLink(link)
                if quality then
                    ApplyBorderColor(self, quality)
                else
                    EnqueueRetry(self, link)
                    tooltipPendingRetry[self] = true
                end
            else
                -- aux path: infer quality from the item name line text color.
                applyFromLineColor(self, 2)
            end
        end
        local link = tooltipActiveLink[self]
        ProcessTooltipLines(self, IsElementSkipLink(link))
        origST(self)
    end
end

-- ============================================================
-- § 8  VARIABLES_LOADED
-- ============================================================

do
    local varFrame = origCreateFrame("Frame")
    varFrame:RegisterEvent("VARIABLES_LOADED")
    varFrame:SetScript("OnEvent", function(self, ev)
        if ev ~= "VARIABLES_LOADED" then return end

        if not ChromaticConfig then ChromaticConfig = {} end
        local cfg = ChromaticConfig
        if cfg.borders      == nil then cfg.borders      = true end
        if cfg.classcolor   == nil then cfg.classcolor   = true end
        if cfg.elementcolor == nil then cfg.elementcolor = true end
        RefreshConfig()

        if not IsAddOnLoaded("MogIt") then
            MogItChecked = true
        end

        local st1 = _G["ShoppingTooltip1"]
        local st2 = _G["ShoppingTooltip2"]
        HookTooltip(st1)
        HookTooltip(st2)
        WrapSetInventoryItem(st1)
        WrapSetInventoryItem(st2)
        WrapShoppingShow(st1)
        WrapShoppingShow(st2)

        HookPetResistances()
        HookCharacterResistances()

        if IsAddOnLoaded("AtlasLoot")  then HookAtlasLoot()  end
        if IsAddOnLoaded("AtlasQuest") then HookAtlasQuest() end

        varFrame:UnregisterEvent("VARIABLES_LOADED")
    end)
end

-- ============================================================
-- § 9  ADDON_LOADED event
-- ============================================================

do
    local atlasLootHooked  = false
    local atlasQuestHooked = false
    local mogItMarked      = false
    local addonFrame = origCreateFrame("Frame")
    addonFrame:RegisterEvent("ADDON_LOADED")
    addonFrame:SetScript("OnEvent", function(self, ev, name)
        if ev ~= "ADDON_LOADED" then return end
        if not atlasLootHooked and name and strfind(name, "AtlasLoot", 1, true) then
            HookAtlasLoot()
            atlasLootHooked = true
        end
        if not atlasQuestHooked and name == "AtlasQuest" then
            HookAtlasQuest()
            atlasQuestHooked = true
        end
        if not mogItMarked and name == "MogIt" then
            -- MogIt just loaded; allow GT:Show to resolve MogItRef on next call.
            MogItChecked = false
            mogItMarked  = true
        end
        if atlasLootHooked and atlasQuestHooked and mogItMarked then
            addonFrame:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

-- ============================================================
-- § 10  Slash commands
-- ============================================================

local MSG_ENABLED  = "|cFF00FF00enabled|r"
local MSG_DISABLED = "|cFFFF0000disabled|r"

local function SlashHandler(msg)
    local cmd = strlower(msg or "")
    local cfg = ChromaticConfig

    if cmd == "class" then
        cfg.classcolor = not cfg.classcolor
        RefreshConfig()
        DEFAULT_CHAT_FRAME:AddMessage("Chromatic: Class color coding " .. (cfg.classcolor and MSG_ENABLED or MSG_DISABLED))
    elseif cmd == "border" then
        cfg.borders = not cfg.borders
        RefreshConfig()
        DEFAULT_CHAT_FRAME:AddMessage("Chromatic: Tooltip borders " .. (cfg.borders and MSG_ENABLED or MSG_DISABLED))
    elseif cmd == "element" then
        cfg.elementcolor = not cfg.elementcolor
        RefreshConfig()
        DEFAULT_CHAT_FRAME:AddMessage("Chromatic: Element color coding " .. (cfg.elementcolor and MSG_ENABLED or MSG_DISABLED))
    elseif cmd == "status" then
        DEFAULT_CHAT_FRAME:AddMessage("Chromatic status:")
        DEFAULT_CHAT_FRAME:AddMessage("Class: "   .. (cfg.classcolor   and MSG_ENABLED or MSG_DISABLED))
        DEFAULT_CHAT_FRAME:AddMessage("Border: "  .. (cfg.borders      and MSG_ENABLED or MSG_DISABLED))
        DEFAULT_CHAT_FRAME:AddMessage("Element: " .. (cfg.elementcolor and MSG_ENABLED or MSG_DISABLED))
    else
        DEFAULT_CHAT_FRAME:AddMessage("Chromatic commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/chromatic class - Toggle class name color coding")
        DEFAULT_CHAT_FRAME:AddMessage("/chromatic border - Toggle tooltip rarity borders")
        DEFAULT_CHAT_FRAME:AddMessage("/chromatic element - Toggle element type color coding")
        DEFAULT_CHAT_FRAME:AddMessage("/chromatic status - Show current settings")
    end
end

SLASH_CHROMATIC1 = "/chromatic"
SLASH_CHROMATIC2 = "/chrc"
SlashCmdList["CHROMATIC"] = SlashHandler