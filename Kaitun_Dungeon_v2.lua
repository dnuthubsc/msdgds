
local DEFAULTS = {
    Enabled             = true,

    DungeonAutoEnter    = true,
    DungeonAutoRun      = true,
    DungeonCombat       = true,
    DungeonCards        = true,
    DungeonSkipAll      = false,
    DungeonAutoEquip    = true,
    WeaponSlot          = "One",
    DungeonStance       = "Behind",
    DungeonDistance     = 3.5,
    DungeonReach        = 2000,

    DungeonLeave        = true,
    DungeonLobbyTimeout = 60,
    AvoidShield         = true,
    BackOffStuds        = 10,
    ComboBackoff        = true,
    ComboBackoffTime    = 1.5,
    DungeonBuy          = "1,000 Exp",
    DungeonBuyKeep      = 0,
    DungeonLoot         = true,
    AntiIdle            = true,
    HUD                 = true,
    HUDKey              = "RightShift",

    Verbose             = true,
}

local globalEnv = (typeof(getgenv) == "function" and getgenv()) or _G
local config = globalEnv.Config or _G.config or {}
for key, value in pairs(DEFAULTS) do
    if config[key] == nil then
        config[key] = value
    end
end
globalEnv.Config = config
_G.config = config

local playersService    = game:GetService("Players")
local runService        = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local workspaceService  = game:GetService("Workspace")
local localPlayer       = playersService.LocalPlayer

local function raiseIdentity()
    local setter = (typeof(setthreadidentity) == "function" and setthreadidentity)
        or (typeof(setidentity) == "function" and setidentity)
        or (typeof(syn) == "table" and syn.set_thread_identity)
        or (typeof(set_thread_identity) == "function" and set_thread_identity)
    if setter then
        pcall(setter, 8)
    end
end

if type(_G.__dhConns) == "table" then
    for _, connection in _G.__dhConns do
        pcall(function() connection:Disconnect() end)
    end
end
_G.__dhConns = {}

local RUN = {}
_G.__dhRun = RUN

local CARD_ORDER = {
    "Second Wind", "Extra Life", "Vampiric", "Second Chance", "Reincarnation",
    "Adrenaline", "Bulwark", "Second Skin",
    "Momentum", "Frenzy", "Heavy Hitter", "Berserk", "Streak",
    "Wildfire", "Deep Freeze", "Plague Bearer", "Venom Fang",
    "Damage", "Max Health", "Max Stamina", "Block Points", "Thick Blood",
    "Endurance Training",
    "Fortune", "Trophy", "Points", "Bounty", "Headhunter",
    "Rerolls", "Loaded Dice", "Lucky Draw", "Prodigy", "Ticket Pack",
    "Mulligan", "Jackpot Floor", "Cheap Seats", "Double Down",
    "Quartermaster", "Hoarder", "Bloodbank", "Medic", "Potion",
    "Weapon Master", "Twin Weapons", "Arsenal", "Twin Souls", "Clan Heir",
    "Forbidden Art", "Skill", "Weapon", "Clan",
    "Skip Floor", "Warcry", "Ignition", "Chill", "Tainted Edge", "Envenomed",
    "Marathon", "Rally", "Split the Take", "Communal Heal", "Parting Gift",
    "Long Night", "Rush Hour", "Handoff", "Reshuffle", "Respec", "Lifeline",
    "Revive", "Skip",
    "Fair Fight", "Boss Hunt", "Elite Guard", "Champion", "Twin Bosses",
    "Ascension", "Boss Rush", "Gold Rush", "Cursed Coin", "Blood Moon",
    "The Horde", "Berserkers", "Thick Skin", "Double Time", "Time Attack",
    "Iron Discipline", "Bleeding Floor", "Bare Hands",
    "Fog of War", "Lights Out", "Heavy Air", "Thin Air", "No Guard",
    "Iron Tower", "Last Stand", "Lone Wolf", "Focused Mind", "Last Rites",
    "Sacrifice", "Blood Pact", "Wager", "Tribute", "Toll Gate",
    "Featherweight", "Glass Cannon", "Glass Floor", "Reincarnated",
    "Tectonic Shift", "Grounded", "Pacifist",
}

local Collection = {
    cards    = false,
    combat   = false,
    reach    = 500,
    distance = 3.5,
    stance   = "Behind",
    skipAll  = false,
    autoRun  = false,
    runs     = 0,
    lastPunch = 0,
    lastCombo = 0,
    combatStatus = "off",
    held     = nil,
    autoEnter = false,
    enterStatus = "idle",
    autoEquip = true,
    equipStatus = "idle",
    slot     = "One",
    fallback = "Skip",

    priority = {
        ["Second Wind"] = true, ["Extra Life"] = true, ["Vampiric"] = true,
        ["Momentum"] = true, ["Frenzy"] = true, ["Damage"] = true,
        ["Max Health"] = true, ["Fortune"] = true, ["Trophy"] = true,
        ["Points"] = true, ["Rerolls"] = true,
    },

    avoid = {
        ["Pacifist"] = true, ["Grounded"] = true, ["Tectonic Shift"] = true,
        ["Glass Cannon"] = true, ["Glass Floor"] = true,
        ["Featherweight"] = true, ["Reincarnated"] = true,
        ["Wager"] = true, ["Tribute"] = true, ["Toll Gate"] = true,
    },

    seen     = (type(_G.__dhSeen) == "table" and _G.__dhSeen) or {},
    hands    = tonumber(_G.__dhHands) or 0,

    status   = "idle",
    lastHand = "none yet",
    lastPick = "none yet",
    target   = "-",
    picks    = 0,
    kills    = 0,
}

_G.__dhSeen = Collection.seen

function Collection.tryRequire(...)
    local node = replicatedStorage
    for _, name in { ... } do
        node = node and node:FindFirstChild(name)
    end
    if node == nil then return nil end
    local ok, loadedModule = pcall(require, node)
    return ok and loadedModule or nil
end

function Collection.alive()
    return _G.__dhRun == RUN and config.Enabled ~= false
end

function Collection.track(connection)
    table.insert(_G.__dhConns, connection)
    return connection
end

function Collection.textOf(node)
    local ok, value = pcall(function() return node.Text end)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
end

function Collection.signalEvent()
    local communication     = replicatedStorage:FindFirstChild("Communication")
    local serverAndClient   = communication and communication:FindFirstChild("ServerAndClient")
    local signals           = serverAndClient and serverAndClient:FindFirstChild("Signals")
    local signalEventModule = signals and signals:FindFirstChild("SignalEvent")
    return signalEventModule and signalEventModule:FindFirstChild("Event")
end

function Collection.request(payload)
    local event = Collection.signalEvent()
    if event == nil then
        return false
    end
    return pcall(function()
        event:FireServer("OuwigaharaRequest", payload)
    end)
end

function Collection.phase()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    local topBar = gui and gui:FindFirstChild("OuwigaharaTopBar", true)
    if topBar == nil then
        return "no run"
    end

    local parts = {}
    for _, name in { "Floor", "Clock", "Value" } do
        local node = topBar:FindFirstChild(name, true)
        local text = node and Collection.textOf(node)
        if text then
            table.insert(parts, text)
        end
    end
    return #parts > 0 and table.concat(parts, "  ") or "no run"
end

function Collection.offers()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    local holder = gui and gui:FindFirstChild("ComponentsHolder")
    local main = holder and holder:FindFirstChild("MainNotificationFrame")
    return main and main:FindFirstChild("OuwigaharaOffers")
end

function Collection.hand()
    local offers = Collection.offers()
    if offers == nil or not offers.Visible then
        return nil
    end

    local cardBoard = offers:FindFirstChild("BBCards")
    local cards = cardBoard and cardBoard:FindFirstChild("Cards")
    if cards == nil then
        return nil
    end

    local slots = {}
    for _, slot in cards:GetChildren() do
        if tonumber(slot.Name) ~= nil and slot:IsA("GuiObject") and slot.Visible then
            table.insert(slots, slot)
        end
    end
    if #slots == 0 then
        return nil
    end
    table.sort(slots, function(a, b) return tonumber(a.Name) < tonumber(b.Name) end)

    local hand = {}
    for _, slot in slots do
        local title = slot:FindFirstChild("Title", true)
        local bottom = slot:FindFirstChild("Bottom", true)
        table.insert(hand, {
            id    = slot.Name,
            title = title and Collection.textOf(title) or "?",
            desc  = bottom and Collection.textOf(bottom) or "",
        })
    end
    return hand
end

function Collection.matches(title, needle)
    return string.find(string.lower(title), string.lower(needle), 1, true) ~= nil
end

function Collection.numberIn(title)
    return tonumber(string.match(title, "%+%s*(%d+%.?%d*)")) or 0
end

function Collection.choose(hand)
    local allowed = {}
    for _, card in hand do
        local banned = false
        for avoidTitle in pairs(Collection.avoid) do
            if Collection.matches(card.title, avoidTitle) then
                banned = true
                break
            end
        end
        if not banned then
            table.insert(allowed, card)
        end
    end

    for _, want in CARD_ORDER do
        if Collection.priority[want] then
            local best
            for _, card in allowed do
                if Collection.matches(card.title, want) then
                    if best == nil or Collection.numberIn(card.title) > Collection.numberIn(best.title) then
                        best = card
                    end
                end
            end
            if best ~= nil then
                return best, want
            end
        end
    end

    if Collection.fallback == "Take first" and allowed[1] ~= nil then
        return allowed[1], "first allowed"
    end
    return nil, "nothing wanted"
end

function Collection.handleHand()
    local hand = Collection.hand()
    if hand == nil then
        Collection.lastKey = nil
        return false
    end

    local key = ""
    for _, card in hand do
        key = key .. card.id .. card.title .. "|"
    end
    if key == Collection.lastKey then
        return false
    end
    Collection.lastKey = key

    local names = {}
    for _, card in hand do
        table.insert(names, card.id .. ":" .. card.title)

        if Collection.seen[card.title] == nil then
            Collection.seen[card.title] = { desc = card.desc, count = 0 }
        end
        Collection.seen[card.title].count = Collection.seen[card.title].count + 1
    end
    Collection.hands = Collection.hands + 1
    _G.__dhHands = Collection.hands
    Collection.lastHand = table.concat(names, "   ")

    local pick, why
    if Collection.skipAll then
        why = "auto skip"
    else
        pick, why = Collection.choose(hand)
    end

    if pick ~= nil then
        Collection.request({ action = "Pick", id = pick.id })
        Collection.lastPick = ("%s (%s)"):format(pick.title, why)
        Collection.picks = Collection.picks + 1
    else
        Collection.request({ action = "Skip" })
        Collection.lastPick = "Skip - " .. tostring(why)
    end
    return true
end

function Collection.getRootPart()
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil or humanoid.Health <= 0 then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

function Collection.allegiance()
    if Collection.allegianceModule ~= nil then
        return Collection.allegianceModule
    end
    local camFolder = replicatedStorage:FindFirstChild("CAM")
    local global = camFolder and camFolder:FindFirstChild("Global")
    local module = global and global:FindFirstChild("Allegiance")
    if module == nil then
        return nil
    end
    local ok, value = pcall(require, module)
    if ok and type(value) == "table" and type(value.AreFriendly) == "function" then
        Collection.allegianceModule = value
        return value
    end
end

function Collection.friendly(model)
    if playersService:GetPlayerFromCharacter(model) ~= nil then
        return true
    end
    local character = localPlayer.Character
    if character == nil then
        return false
    end
    local allegiance = Collection.allegiance()
    if allegiance == nil then
        return false
    end
    local ok, value = pcall(allegiance.AreFriendly, character, model)
    return ok and value == true
end

function Collection.modelOf(entry)
    if entry:IsA("Model") then
        return entry
    end
    local named = entry:FindFirstChild(entry.Name)
    if named ~= nil and named:IsA("Model") then
        return named
    end
    for _, child in entry:GetChildren() do
        if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
            return child
        end
    end
end

function Collection.nearest()
    local rootPart = Collection.getRootPart()
    if rootPart == nil then
        return nil
    end

    local humanoids = workspaceService:FindFirstChild("Humanoids")
    local regions = humanoids and humanoids:FindFirstChild("Regions")

    local best, bestDist
    for _, region in (regions and regions:GetChildren() or {}) do
        local active = region:FindFirstChild("ActiveNpcs")
        for _, entry in (active and active:GetChildren() or {}) do
            local npc = Collection.modelOf(entry)
            if npc ~= nil and not Collection.friendly(npc) then
                local humanoid = npc:FindFirstChildOfClass("Humanoid")
                if humanoid ~= nil and humanoid.Health > 0 then
                    local ok, pivot = pcall(function() return npc:GetPivot() end)
                    if ok then
                        local dist = (pivot.Position - rootPart.Position).Magnitude
                        if dist <= Collection.reach and (bestDist == nil or dist < bestDist) then
                            best, bestDist = npc, dist
                        end
                    end
                end
            end
        end
    end
    return best, bestDist
end

function Collection.place(rootPart, targetCFrame)
    local distance = (Collection.distance or 3.5)
        + (Collection.shielded and Collection.blockStuds or 0)
        + (Collection.resting() and 14 or 0)

    local spot
    if Collection.stance == "Above" then
        spot = targetCFrame * CFrame.new(0, distance, 0)
    elseif Collection.stance == "Underground" then
        spot = targetCFrame * CFrame.new(0, -distance, 0)
    else
        spot = targetCFrame * CFrame.new(0, 0, distance)
    end

    local upVector = targetCFrame.UpVector
    local lookDirection = targetCFrame.Position - spot.Position
    if lookDirection.Magnitude < 0.05 then
        lookDirection = targetCFrame.LookVector
    end
    if math.abs(lookDirection.Unit:Dot(upVector)) > 0.99 then
        upVector = targetCFrame.LookVector
    end

    rootPart.CFrame = CFrame.lookAt(spot.Position, spot.Position + lookDirection, upVector)

    rootPart.AssemblyLinearVelocity  = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
end

Collection.avoidBlock   = true
Collection.blockStuds   = 10
Collection.comboBackoff = true
Collection.backoffTime  = 1.5
Collection.backoffUntil = 0
Collection.shielded     = false

function Collection.isShielded(model)
    local overhead = model and model:FindFirstChild("OverHead", true)
    local holder = overhead and overhead:FindFirstChild("Holder")
    return holder ~= nil and holder:FindFirstChild("Frame") ~= nil
end

function Collection.resting()
    return os.clock() < Collection.backoffUntil
end

task.spawn(function()
    local service = replicatedStorage:WaitForChild("Player_Service", 20)
    local values = service and service:WaitForChild("Values", 20)
    local mine = values and values:WaitForChild(localPlayer.Name, 20)
    local tracker = mine and mine:WaitForChild("ComboTrackerClient", 20)
    if tracker == nil or not tracker:IsA("IntValue") then
        return
    end
    Collection.track(tracker.Changed:Connect(function(value)
        if Collection.comboBackoff and value >= 5 then
            Collection.backoffUntil = os.clock() + Collection.backoffTime
        end
    end))
end)

local Checker        = Collection.tryRequire("CAM", "Global", "Checker")
local Combat_presets = Collection.tryRequire("CAM", "Global", "Combat_presets")
local Character_info = Collection.tryRequire("CAM", "Global", "Character_info_provider")
local Items          = Collection.tryRequire("CAM", "Global", "Collectibles", "Items")

local camRoot    = replicatedStorage:FindFirstChild("CAM")
Collection.Animations = replicatedStorage:FindFirstChild("Assets")
pcall(function()
    Collection.CurPower = camRoot.Client.Controllers.Skills_Provider:FindFirstChild("CurPower")
end)


function Collection.resolveCombat()
    Collection.punch, Collection.Do = nil, nil
    local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
    local clientRoot    = playerScripts and playerScripts:FindFirstChild("CU")
    Collection.combatScript = clientRoot and clientRoot:FindFirstChild("Combat")
    Collection.ComboValue   = Collection.combatScript and Collection.combatScript:FindFirstChild("ComboValue")

    if Collection.combatScript ~= nil then
        if typeof(getsenv) == "function" then
            local ok, env = pcall(getsenv, Collection.combatScript)
            if ok and type(env) == "table" and type(rawget(env, "punch")) == "function" then
                Collection.punch = rawget(env, "punch")
            end
        end
        local combatModule = Collection.combatScript:FindFirstChild("Main_Combat_Script_Client")
        if combatModule ~= nil then
            local ok, loaded = pcall(require, combatModule)
            if ok and type(loaded) == "table" and type(loaded.Do) == "function" then
                Collection.Do = loaded.Do
            end
        end
    end

    Collection.route = Collection.punch and 1 or Collection.Do and 2 or 3
    Collection.routeName = Collection.route == 1 and "punch() via getsenv"
        or Collection.route == 2 and "Do() via require"
        or "raw FireServer"
    Collection.resolvedAt = os.clock()
end

function Collection.combatStale()
    return Collection.combatScript == nil or Collection.ComboValue == nil
        or Collection.combatScript.Parent == nil or Collection.ComboValue.Parent == nil
end

Collection.resolveCombat()

function Collection.equippedCombat()
    if localPlayer.Character == nil or Collection.Animations == nil then
        return nil
    end
    if Collection.CurPower ~= nil then
        for _, power in ipairs(string.split(Collection.CurPower.Value, ",")) do
            if Collection.Animations:FindFirstChild(power .. "_Combat_Anims") then
                return power
            end
        end
    end
    if Character_info ~= nil then
        local ok, tool = pcall(Character_info.Get_equipped_tool, localPlayer)
        if ok and tool ~= nil then
            local item = Items and Items[tool.Name]
            if (item ~= nil and item.HasCombat)
                or Collection.Animations:FindFirstChild(tool.Name .. "_Combat_Anims") then
                return tool.Name
            end
        end
    end
end

function Collection.presetFromTools()
    if Combat_presets == nil then return nil end

    local humanoidsFolder = workspaceService:FindFirstChild("Humanoids")
    local character = (humanoidsFolder and humanoidsFolder:FindFirstChild(localPlayer.Name))
        or localPlayer.Character
    local toolFolder = character and character:FindFirstChild("Tool_Accessories")
    if toolFolder == nil then return nil end

    local tools = toolFolder:GetChildren()
    if #tools == 0 then
        return Combat_presets.Presets["Combat"] and "Combat" or nil
    end

    local function presetFor(name)
        if Combat_presets.Presets[name] then return name end
        local item = Items and Items[name]
        local mapped = item and item.CombatPreset
        if mapped and Combat_presets.Presets[mapped] then return mapped end
    end

    for _, model in tools do
        if not string.find(model.Name, "Sheathed") then
            local found = presetFor(model.Name)
            if found then return found end
        end
    end
    for _, model in tools do
        local found = presetFor((string.gsub(model.Name, "Sheathed%d*$", "")))
        if found then return found end
    end
end

function Collection.resolvePreset()
    if Combat_presets == nil then return nil end

    local fromTools = Collection.presetFromTools()
    if fromTools ~= nil then
        return Combat_presets.Presets[fromTools], fromTools, nil
    end

    local equipped = Collection.equippedCombat()
    if equipped == nil then return nil end

    local preset = Combat_presets.Presets[equipped]
    if preset ~= nil then return preset, equipped, nil end

    local item = Items and Items[equipped]
    local presetName, powerName
    if item == nil or (item.Breathing == nil and not item.HasCombat and item.CombatPreset == nil) then
        presetName, powerName = equipped, nil
    else
        presetName, powerName = item.CombatPreset or "Regular Katana", equipped
    end
    return Combat_presets.Presets[presetName], presetName, powerName
end

function Collection.gapFor(preset)
    local maxCombo = preset.Max or 5
    local gap = preset.default or 0.25
    local current = Collection.ComboValue and Collection.ComboValue.Value or 1
    if Collection.lastCombo >= maxCombo and current < maxCombo then
        gap = preset.final or gap
    end
    return gap
end

function Collection.combatStep()
    local preset, presetName, powerName = Collection.resolvePreset()
    if preset == nil or presetName == nil then
        Collection.combatStatus = "no combat equipped"
        return nil
    end
    if Collection.ComboValue == nil then
        Collection.combatStatus = "no ComboValue - is CU.Combat running?"
        return nil
    end

    local gap = Collection.gapFor(preset)
    local since = os.clock() - Collection.lastPunch
    if gap >= since then
        Collection.combatStatus = ("cooling down (%.2fs)"):format(gap - since)
        return gap - since
    end

    if Checker ~= nil and Checker.check(localPlayer, "combat") ~= true then
        Collection.combatStatus = "blocked by Checker (stun / ragdoll / cutscene)"
        return nil
    end

    local maxCombo = preset.Max or 5
    local value = Collection.ComboValue.Value

    if Collection.route == 2 then
        local ok, result = pcall(Collection.Do, Collection.ComboValue, preset, presetName, powerName)
        if not ok then return nil end
        Collection.lastCombo = (type(result) == "table" and result.combovalue) or value
    else
        local beforeSwing = (preset.delay_before_swing and preset.delay_before_swing[value])
            or preset.default_before_swing
            or (Combat_presets and Combat_presets.Default_Swing_Wait) or 0
        local beforeHit = (preset.delay_before_hit and preset.delay_before_hit[value])
            or preset.default_before_hit or beforeSwing

        local speed = 1
        if Combat_presets and type(Combat_presets.attackSpeedMult) == "function" then
            local okMult, multiplier = pcall(Combat_presets.attackSpeedMult, localPlayer)
            if okMult and type(multiplier) == "number" and multiplier > 0 then
                speed = multiplier
            end
        end

        local event = Collection.signalEvent()
        if event == nil then
            Collection.combatStatus = "SignalEvent missing"
            return nil
        end

        local okFire, fireError = pcall(function()
            event:FireServer("Combat_Service", presetName, value, false,
                (beforeHit - beforeSwing) / speed, false, nil)
        end)
        if not okFire then
            Collection.combatStatus = "error: " .. tostring(fireError)
            return nil
        end
        Collection.lastCombo = value
    end

    if Combat_presets then
        Combat_presets.Last_Combo = value
    end
    Collection.ComboValue.Value = (value == maxCombo or value == 7) and 1 or value + 1
    Collection.lastPunch = os.clock()
    Collection.combatStatus = ("punching %s combo %d/%d"):format(presetName, value, maxCombo)
    return Collection.gapFor(preset)
end

function Collection.swing()
    if Collection.combatStale() and os.clock() - (Collection.resolvedAt or 0) > 2 then
        Collection.resolveCombat()
    end

    if Collection.route == 1 then
        local ok, nextGap = pcall(Collection.punch)
        if not ok then
            Collection.combatStatus = "punch() errored: " .. tostring(nextGap)
        elseif nextGap == nil then
            Collection.combatStatus = "punch() refused - using combatStep"
            local okStep, gap = pcall(Collection.combatStep)
            return (okStep and gap) or 0.25
        else
            Collection.combatStatus = ("punching (next in %.2fs)"):format(nextGap)
            return nextGap
        end
        return 0.25
    end

    local ok, gap = pcall(Collection.combatStep)
    if not ok then
        Collection.combatStatus = "error: " .. tostring(gap)
    end
    return (ok and gap) or 0.25
end

Collection.QUEST  = "Ill find the forge(Lv 65)"
Collection.PORTAL = Vector3.new(-1594, 1003, 1145)
Collection.PAD    = "OuwigaharaPromptPad"

function Collection.questState()
    local playerService = replicatedStorage:FindFirstChild("Player_Service")
    local dataFolder    = playerService and playerService:FindFirstChild("Data")
    local mine          = dataFolder and dataFolder:FindFirstChild(localPlayer.Name)
    local slotEquipped  = mine and mine:FindFirstChild("slotEquipped")
    local slots = mine and mine:FindFirstChild("slots")
    local slot = slots and slots:FindFirstChild("Slot" .. tostring(slotEquipped and slotEquipped.Value or 1))
    local quests = slot and slot:FindFirstChild("Quests")
    if quests == nil then
        return "unknown"
    end

    for _, folder in { "Completed", "Holder" } do
        local questList = quests:FindFirstChild(folder)
        for _, quest in (questList and questList:GetChildren() or {}) do
            if quest.Name == Collection.QUEST then
                return folder == "Completed" and "completed" or "held"
            end
        end
    end
    return "none"
end

function Collection.portalPrompt()
    local map = workspaceService:FindFirstChild("Map")
    local pad = map and map:FindFirstChild(Collection.PAD)
    local prompt = pad and pad:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt ~= nil then
        return prompt
    end
    for _, descendant in workspaceService:GetDescendants() do
        if descendant:IsA("ProximityPrompt") and descendant.Name == "Ouwigahara"
            and descendant.ActionText == "Enter" then
            return descendant
        end
    end
end

function Collection.enterDungeon()
    if game.PlaceId == 75556147183481 then
        return true, "already in Ouwigahara"
    end
    if game.PlaceId ~= 136406881576517 then
        return false, "not in Ouwland"
    end

    if Collection.outOfLives() then
        return false, "out of lives - the portal will not take you again"
    end

    local quest = Collection.questState()
    if quest == "none" then
        return false, "quest not done - talk to Blacksmith Togane first"
    end

    local rootPart = Collection.getRootPart()
    if rootPart == nil then
        return false, "no character"
    end

    rootPart.CFrame = CFrame.new(Collection.PORTAL + Vector3.new(0, 3, 4))
    rootPart.AssemblyLinearVelocity  = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero

    local prompt
    local deadline = os.clock() + 8
    repeat
        prompt = Collection.portalPrompt()
        if prompt == nil then
            task.wait(0.3)
        end
    until prompt ~= nil or os.clock() > deadline

    if prompt == nil then
        return false, "portal prompt never streamed in"
    end
    if not prompt.Enabled then
        return false, "portal disabled - is the forge quest completed?"
    end

    local fireFunction = (typeof(fireproximityprompt) == "function" and fireproximityprompt)
        or (typeof(fireprox) == "function" and fireprox)
        or (typeof(syn) == "table" and syn.fireproximityprompt)
    if fireFunction then
        pcall(fireFunction, prompt)
    else
        pcall(function()
            local hold = prompt.HoldDuration
            prompt.HoldDuration = 0
            prompt:InputHoldBegin()
            prompt:InputHoldEnd()
            prompt.HoldDuration = hold
        end)
    end

    return true, "portal fired"
end

Collection.SLOT_NUMBER = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5 }

function Collection.equippedSlotValue()
    local folder = localPlayer:FindFirstChild("Items_Config")
    return folder and folder:FindFirstChild("Equipped") or nil
end

function Collection.weaponDrawn()
    local equipped = Collection.equippedSlotValue()
    return equipped ~= nil and equipped.Value ~= 0
end

function Collection.filledSlots()
    local playerService = replicatedStorage:FindFirstChild("Player_Service")
    local dataFolder = playerService and playerService:FindFirstChild("Data")
    local mine = dataFolder and dataFolder:FindFirstChild(localPlayer.Name)
    local slotEquipped = mine and mine:FindFirstChild("slotEquipped")
    local slots = mine and mine:FindFirstChild("slots")
    local slot = slots and slots:FindFirstChild("Slot" .. tostring(slotEquipped and slotEquipped.Value or 1))
    local inventory = slot and slot:FindFirstChild("Inventory")
    local toolbar = inventory and inventory:FindFirstChild("Toolbar")

    local filled = {}
    for _, name in { "One", "Two", "Three", "Four", "Five" } do
        local entry = toolbar and toolbar:FindFirstChild(name)
        if entry ~= nil and tonumber(entry.Value) ~= nil and entry.Value ~= 0 then
            table.insert(filled, name)
        end
    end
    return filled
end

function Collection.drawWeapon()
    if Collection.weaponDrawn() then
        return true, "already drawn"
    end

    local want = Collection.slot
    local filled = Collection.filledSlots()
    if Collection.SLOT_NUMBER[want] == nil or not table.find(filled, want) then
        want = filled[1]
    end
    if want == nil then
        return false, "toolbar is empty"
    end

    local number = Collection.SLOT_NUMBER[want]
    local equipped = Collection.equippedSlotValue()

    if equipped ~= nil then
        local ok = pcall(function() equipped.Value = number end)
        if not ok then
            return false, "could not set Items_Config.Equipped"
        end
    else
        local event = Collection.signalEvent()
        if event == nil then
            return false, "SignalEvent missing"
        end
        pcall(function() event:FireServer("Item_Equip", number) end)
    end

    local deadline = os.clock() + 3
    repeat
        task.wait(0.2)
    until Collection.weaponDrawn() or os.clock() > deadline

    if Collection.weaponDrawn() then
        return true, "drew slot " .. want
    end
    return false, "sent but nothing drew"
end

function Collection.hearts()
    local value = localPlayer:GetAttribute("Hearts")
    if value == nil then
        return nil
    end
    return tonumber(value) or 0
end

function Collection.outOfLives()
    local hearts = Collection.hearts()
    return hearts ~= nil and hearts <= 0
end

function Collection.state()
    return tostring(game:GetService("Workspace"):GetAttribute("MinigameState") or "?")
end

function Collection.climbing()
    return Collection.state() == "Climbing"
end

function Collection.readied()
    return localPlayer:GetAttribute("Readied") == true
end

function Collection.startPrompt()
    local map = workspaceService:FindFirstChild("Map")
    local lobby = map and map:FindFirstChild("Minigame Map")
    local pad = lobby and lobby:FindFirstChild("StartPad", true)
    if pad ~= nil then
        local prompt = pad:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt ~= nil then
            return prompt, pad
        end
    end

    for _, descendant in workspaceService:GetDescendants() do
        if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("PromptStyle") == "Card" then
            return descendant, descendant.Parent
        end
    end
end

function Collection.firePrompt(prompt)
    local fireFunction = (typeof(fireproximityprompt) == "function" and fireproximityprompt)
        or (typeof(fireprox) == "function" and fireprox)
        or (typeof(syn) == "table" and syn.fireproximityprompt)
    if fireFunction then
        return pcall(fireFunction, prompt)
    end
    return pcall(function()
        local hold = prompt.HoldDuration
        prompt.HoldDuration = 0
        prompt:InputHoldBegin()
        prompt:InputHoldEnd()
        prompt.HoldDuration = hold
    end)
end

function Collection.readyUp()
    if Collection.readied() then
        return true, "already readied"
    end
    if Collection.climbing() then
        return false, "already climbing"
    end
    if Collection.outOfLives() then
        return false, "out of lives - this run is finished"
    end

    local prompt, pad = Collection.startPrompt()
    if prompt == nil then
        return false, "no StartPad prompt - not in the lobby?"
    end

    local rootPart = Collection.getRootPart()
    if rootPart ~= nil and pad ~= nil then
        local ok, pivot = pcall(function()
            return pad:IsA("Model") and pad:GetPivot() or CFrame.new(pad.Position)
        end)
        if ok then
            rootPart.CFrame = CFrame.new(pivot.Position + Vector3.new(0, 4, 0))
            rootPart.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.4)
        end
    end

    Collection.firePrompt(prompt)

    local deadline = os.clock() + 4
    repeat
        task.wait(0.2)
    until Collection.readied() or Collection.climbing() or os.clock() > deadline

    if Collection.readied() or Collection.climbing() then
        return true, "readied"
    end
    return false, "prompt fired but never readied"
end

function Collection.syncConfig()
    Collection.autoEnter = config.DungeonAutoEnter == true
    Collection.autoRun   = config.DungeonAutoRun == true
    Collection.combat    = config.DungeonCombat == true
    Collection.cards     = config.DungeonCards == true
    Collection.skipAll   = config.DungeonSkipAll == true
    Collection.autoEquip = config.DungeonAutoEquip == true
    Collection.slot      = tostring(config.WeaponSlot or "One")
    Collection.stance    = tostring(config.DungeonStance or "Behind")
    Collection.distance  = tonumber(config.DungeonDistance) or 3.5
    Collection.reach     = tonumber(config.DungeonReach) or 2000
    Collection.avoidBlock   = config.AvoidShield ~= false
    Collection.blockStuds   = tonumber(config.BackOffStuds) or 10
    Collection.comboBackoff = config.ComboBackoff ~= false
    Collection.backoffTime  = tonumber(config.ComboBackoffTime) or 1.5
    Collection.autoLoot     = config.DungeonLoot ~= false
    Collection.buyKeep      = tonumber(config.DungeonBuyKeep) or 0
    local buy = {}
    if type(config.DungeonBuy) == "table" then
        for _, item in config.DungeonBuy do
            table.insert(buy, tostring(item))
        end
    elseif type(config.DungeonBuy) == "string" then
        for item in string.gmatch(config.DungeonBuy, "[^;|]+") do
            item = string.gsub(item, "^%s*(.-)%s*$", "%1")
            if item ~= "" then
                table.insert(buy, item)
            end
        end
    end
    Collection.buyList = buy
end

Collection.syncConfig()

function Collection.log(...)
    if config.Verbose then
        print("[dungeon]", ...)
    end
end

if config.AntiIdle then
    if _G.__kaitunAntiIdle ~= nil then
        pcall(function() _G.__kaitunAntiIdle:Disconnect() end)
        _G.__kaitunAntiIdle = nil
    end

    local ok, virtualUser = pcall(game.GetService, game, "VirtualUser")
    if ok and virtualUser ~= nil then
        _G.__kaitunAntiIdle = localPlayer.Idled:Connect(function()
            pcall(function()
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.new())
            end)
            Collection.log("anti-idle: idle kick suppressed")
        end)
        Collection.log("anti-idle: armed")
    else
        Collection.log("anti-idle: VirtualUser unavailable -", tostring(virtualUser))
    end
end

Collection.netModules = {
    Teleporter = Collection.tryRequire("CAM", "Client", "Modules", "Teleporter"),
    SignalFn   = Collection.tryRequire("Communication", "ServerAndClient", "Signals", "SignalFunction"),
}

function Collection.serverRequest(settings, ui)
    if Collection.netModules.Teleporter ~= nil and type(Collection.netModules.Teleporter.Request) == "function" then
        local fired, ok, detail = pcall(Collection.netModules.Teleporter.Request, settings, ui)
        if not fired then
            return false, "Teleporter.Request errored: " .. tostring(ok)
        end
        return ok == true, tostring(detail or (ok and "teleporting" or "refused"))
    end
    if Collection.netModules.SignalFn ~= nil and type(Collection.netModules.SignalFn.ToServer) == "function" then
        local fired, a, b = pcall(Collection.netModules.SignalFn.ToServer, "TeleportServer", settings)
        if not fired then
            return false, "TeleportServer errored: " .. tostring(a)
        end
        return a == true, tostring(b or "sent")
    end
    return false, "Teleporter module missing"
end

function Collection.loaderFor(url, file, fallback)
    if type(url) == "string" and url ~= "" then
        return ("loadstring(game:HttpGet(%q))()"):format(url)
    end
    return ("loadstring(readfile(%q))()"):format(tostring(file or fallback))
end

function Collection.queueReturn(dungeonOff)
    if dungeonOff == nil then
        dungeonOff = true
    end

    local queue = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
        or (typeof(queueonteleport) == "function" and queueonteleport)
        or (typeof(syn) == "table" and syn.queue_on_teleport)
    if queue == nil then
        return "no queue_on_teleport"
    end

    local clear = (typeof(clear_teleport_queue) == "function" and clear_teleport_queue)
        or (typeof(clearteleportqueue) == "function" and clearteleportqueue)
        or (typeof(clearqueueonteleport) == "function" and clearqueueonteleport)
    if clear ~= nil then
        pcall(clear)
    end

    local parts = {}
    if dungeonOff then
        table.insert(parts, '["Dungeon"]=false')
    end
    for key, value in pairs(config) do
        local kind = type(value)
        if not (dungeonOff and key == "Dungeon") then
            if kind == "string" then
                table.insert(parts, ("[%q]=%q"):format(key, value))
            elseif kind == "number" or kind == "boolean" then
                table.insert(parts, ("[%q]=%s"):format(key, tostring(value)))
            end
        end
    end

    local body
    if globalEnv.amitoofast_loader then
        body = Collection.loaderFor(config.LoaderUrl, config.LoaderFile, "amitoofast.lua")
    else
        body = ("if game.PlaceId == %d then %s else %s end"):format(75556147183481,
            Collection.loaderFor(config.DungeonUrl, config.DungeonFile, "Kaitun_Dungeon_v2.lua"),
            Collection.loaderFor(config.RequeueUrl, config.RequeueFile, "Kaitun_v2.lua"))
    end

    local chunk = ("task.wait(%d) getgenv().Config = {%s} %s")
        :format(tonumber(config.RequeueDelay) or 8, table.concat(parts, ","), body)
    local ok = pcall(queue, chunk)
    if not ok then
        return "refused by the executor"
    end
    return dungeonOff and "armed (dungeon off)" or "armed"
end

Collection.leaving = false

function Collection.leave(reason)
    if Collection.leaving then
        return
    end
    Collection.leaving = true
    Collection.hudNote = "leaving for Ouwland - " .. tostring(reason)

    if not Collection.spentRun and Collection.runPoints() > 0 then
        Collection.spentRun = true
        Collection.log("shop: " .. Collection.spend(reason))
    end

    Collection.log(("run over - %s. return queue: %s"):format(reason, Collection.queueReturn()))
    local ok, detail = Collection.serverRequest({ placeId = 136406881576517, allowFallback = true },
        { Title = "Travelling", SubTitle = "Ouwland" })
    Collection.log("leaving for Ouwland: " .. tostring(detail))

    if not ok then
        task.delay(10, function() Collection.leaving = false end)
    end
end

if game.PlaceId == 75556147183481 then
    Collection.log("return queue: " .. Collection.queueReturn())
end

Collection.offersRoot = Collection.offers()
if Collection.offersRoot ~= nil then
    Collection.track(Collection.offersRoot:GetPropertyChangedSignal("Visible"):Connect(function()
        if Collection.offersRoot.Visible and Collection.cards then
            task.wait(0.5)
            pcall(Collection.handleHand)
        end
    end))
end

task.spawn(function()
    while Collection.alive() do
        if Collection.cards then
            pcall(Collection.handleHand)
        end
        task.wait(2)
    end
end)

Collection.track(runService.Heartbeat:Connect(function()
    if not Collection.alive() or not Collection.combat then
        return
    end

    local enemy = Collection.held
    if enemy == nil or enemy.Parent == nil then
        return
    end

    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    if humanoid == nil or humanoid.Health <= 0 then
        Collection.held = nil
        return
    end

    local rootPart = Collection.getRootPart()
    if rootPart == nil then
        return
    end

    Collection.shielded = Collection.avoidBlock and Collection.isShielded(enemy) or false

    local ok, pivot = pcall(function() return enemy:GetPivot() end)
    if ok then
        Collection.place(rootPart, pivot)
    end
end))

task.spawn(function()
    while Collection.alive() do
        if Collection.autoEquip and (Collection.combat or Collection.autoRun) and not Collection.weaponDrawn() then
            local ok, detail = Collection.drawWeapon()
            Collection.equipStatus = tostring(detail)
            task.wait(ok and 2 or 5)
        else
            task.wait(2)
        end
    end
end)

task.spawn(function()
    while Collection.alive() do
        if Collection.autoEnter and game.PlaceId == 136406881576517 and not Collection.outOfLives() then
            Collection.queueReturn(false)
            local ok, detail = Collection.enterDungeon()
            Collection.enterStatus = tostring(detail)
            Collection.log("enter: " .. tostring(detail))
            task.wait(ok and 12 or 6)
        else
            task.wait(2)
        end
    end
end)

Collection.PRICES = {
    ["1,000 Exp"]             = 3500,
    ["1,000 Wen"]             = 2500,
    ["Refinement Ore"]        = 1500,
    ["Mythic Refinement Ore"] = 30000,
}
Collection.buyList   = {}
Collection.buyKeep   = 0
Collection.buyStatus = "idle"
Collection.spentRun  = false
Collection.autoLoot  = true

function Collection.priceOf(item)
    local price = Collection.PRICES[item]
    if price == nil and string.sub(item, -8) == " Mastery" then
        price = 3000
    end
    return price
end

function Collection.runPoints()
    return tonumber(localPlayer:GetAttribute("RunPoints")) or 0
end

function Collection.spend(reason)
    if #Collection.buyList == 0 then
        return "nothing to buy configured"
    end
    if workspaceService:GetAttribute("MinigameRunFreshStart") == true then
        Collection.buyStatus = "roguelike run - the shops keep nothing"
        return Collection.buyStatus
    end

    local remote = replicatedStorage:FindFirstChild("Communication")
    remote = remote and remote:FindFirstChild("ServerAndClient")
    remote = remote and remote:FindFirstChild("Signals")
    remote = remote and remote:FindFirstChild("SignalFunction")
    remote = remote and remote:FindFirstChild("Function")
    if remote == nil then
        Collection.buyStatus = "SignalFunction missing"
        return Collection.buyStatus
    end

    local bought = {}
    for _, item in Collection.buyList do
        local price = Collection.priceOf(item)
        local count = price and math.floor((Collection.runPoints() - Collection.buyKeep) / price) or 0
        if count > 0 then
            local ok, result = pcall(function()
                return remote:InvokeServer("PurchaseSelection", { [item] = count })
            end)
            table.insert(bought, ("%s x%d %s"):format(item, count,
                (ok and result) and "bought" or ("refused (" .. tostring(result) .. ")")))
            task.wait(0.5)
        end
    end

    Collection.buyStatus = ("%s - %s, %d points left"):format(tostring(reason),
        #bought > 0 and table.concat(bought, ", ") or "nothing affordable", Collection.runPoints())
    return Collection.buyStatus
end

task.spawn(function()
    local stoppedAt = nil
    while Collection.alive() do
        local hearts = Collection.hearts()
        if Collection.climbing() and (hearts == nil or hearts > 0) then
            Collection.spentRun, stoppedAt = false, nil
        elseif not Collection.climbing() then
            stoppedAt = stoppedAt or os.clock()
        end

        local outOfHearts = hearts ~= nil and hearts <= 0
        local stopped = stoppedAt ~= nil and os.clock() - stoppedAt > 3
        if not Collection.spentRun and #Collection.buyList > 0 and Collection.runPoints() > 0
            and (outOfHearts or stopped) then
            Collection.spentRun = true
            print("[dungeon] shop: " .. Collection.spend(outOfHearts and "out of hearts" or "climb ended"))
        end
        task.wait(0.5)
    end
end)

function Collection.lootOnce()
    local fired = 0
    for _, folderName in { "LootDrops", "Chests" } do
        local folder = workspaceService:FindFirstChild(folderName)
        for _, item in (folder and folder:GetChildren() or {}) do
            local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt ~= nil and prompt.Enabled and Collection.firePrompt(prompt) then
                fired = fired + 1
            end
        end
    end
    return fired
end

task.spawn(function()
    while Collection.alive() do
        if Collection.autoLoot then
            pcall(Collection.lootOnce)
        end
        task.wait(1)
    end
end)

task.spawn(function()
    local wasClimbing = false
    local idleSince = nil

    while Collection.alive() do
        Collection.syncConfig()

        if game.PlaceId ~= 75556147183481 then
            task.wait(2)
        elseif Collection.climbing() then
            wasClimbing = true
            idleSince = nil
            task.wait(1)
        elseif wasClimbing then
            task.wait(5)
            if not Collection.climbing() then
                wasClimbing = false
                Collection.runs = Collection.runs + 1
                Collection.log(("climb ended - %d cards picked"):format(Collection.picks))
                if config.DungeonLeave then
                    Collection.leave("climb ended")
                end
            end
        elseif Collection.outOfLives() then
            if config.DungeonLeave then
                Collection.leave("out of lives")
            end
            task.wait(5)
        else
            idleSince = idleSince or os.clock()
            local idle = os.clock() - idleSince

            if config.DungeonLeave and idle > (tonumber(config.DungeonLobbyTimeout) or 60) then
                Collection.leave(("nothing to fight in the lobby for %ds"):format(math.floor(idle)))
                task.wait(5)
            elseif Collection.autoRun and not Collection.readied() then
                local ok, detail = Collection.readyUp()
                Collection.lastReady = tostring(detail)
                Collection.log("ready up: " .. tostring(detail))
                task.wait(ok and 2 or 4)
            else
                task.wait(1)
            end
        end
    end
end)

task.spawn(function()
    while Collection.alive() do
        if not Collection.combat then
            Collection.target = "-"
            task.wait(0.5)
        else
            local enemy, dist = Collection.nearest()
            if enemy == nil then
                Collection.target = "-"
                Collection.held = nil
                task.wait(0.5)
            else
                Collection.target = ("%s (%.0f)"):format(enemy.Name, dist or -1)
                Collection.held = enemy
                if Collection.resting() then
                    Collection.combatStatus = "finisher landed - backing off"
                    task.wait(0.1)
                elseif Collection.shielded then
                    Collection.combatStatus = "waiting - target still blocking"
                    task.wait(0.2)
                else
                    task.wait(Collection.swing())
                end
            end
        end
    end
end)

task.spawn(function()
    local last
    while Collection.alive() do
        local held = Collection.held
        local line = ("state=%s%s hearts=%s target=%s picked=%d"):format(
            Collection.state(), Collection.readied() and "(readied)" or "",
            tostring(Collection.hearts() or "-"),
            held ~= nil and held.Name or "-", Collection.picks)
        if line ~= last then
            last = line
            Collection.log(line)
        end
        task.wait(2)
    end
end)

if config.HUD then
    local parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")

    local old = parent:FindFirstChild("amitoofast_hud")
    if old then
        pcall(function() old:Destroy() end)
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "amitoofast_hud"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 9999
    gui.Parent = parent

    local dim = Instance.new("Frame")
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 0.12
    dim.BorderSizePixel = 0
    dim.Parent = gui

    local function label(name, text, size, posScale, weight, colour)
        local textLabel = Instance.new("TextLabel")
        textLabel.Name = name
        textLabel.BackgroundTransparency = 1
        textLabel.Size = UDim2.new(1, -40, 0, size + 8)
        textLabel.Position = UDim2.new(0, 20, posScale, 0)
        textLabel.Font = weight
        textLabel.TextSize = size
        textLabel.TextColor3 = colour or Color3.fromRGB(255, 255, 255)
        textLabel.TextStrokeTransparency = 0.6
        textLabel.Text = text
        textLabel.Parent = dim
        return textLabel
    end

    local hud = {}
    hud.name  = label("name",  localPlayer.Name,      26, 0.16, Enum.Font.GothamBold)
    hud.state = label("state", "Status: starting...", 20, 0.22, Enum.Font.Gotham)
    hud.brand = Instance.new("TextButton")
    hud.brand.Name = "brand"
    hud.brand.AutoButtonColor = false
    hud.brand.BackgroundTransparency = 1
    hud.brand.Size = UDim2.new(1, -40, 0, 54)
    hud.brand.Position = UDim2.new(0, 20, 0.46, 0)
    hud.brand.Font = Enum.Font.GothamBlack
    hud.brand.TextSize = 46
    hud.brand.TextColor3 = Color3.fromRGB(120, 200, 255)
    hud.brand.TextStrokeTransparency = 0.6
    hud.brand.Text = "amitoofast"
    hud.brand.Parent = dim
    hud.money  = label("money",  "", 24, 0.78, Enum.Font.GothamBold, Color3.fromRGB(255, 215, 120))
    hud.info   = label("info",   "", 20, 0.84, Enum.Font.Gotham,     Color3.fromRGB(180, 230, 180))
    hud.timers = label("timers", "", 20, 0.90, Enum.Font.Gotham,     Color3.fromRGB(215, 215, 215))

    local shown = true
    local function setShown(visible)
        shown = visible and true or false
        dim.BackgroundTransparency = shown and 0.12 or 1
        for _, part in { hud.name, hud.state, hud.money, hud.info, hud.timers } do
            part.Visible = shown
        end
        hud.brand.TextTransparency = shown and 0 or 0.55
        hud.brand.TextStrokeTransparency = shown and 0.6 or 0.9
        return shown
    end

    Collection.track(hud.brand.MouseButton1Click:Connect(function()
        setShown(not shown)
    end))

    local keyName = tostring(config.HUDKey or "RightShift")
    local okKey, keyCode = pcall(function() return Enum.KeyCode[keyName] end)
    if okKey and keyCode then
        Collection.track(game:GetService("UserInputService").InputBegan:Connect(function(input, typing)
            if typing then return end
            if input.KeyCode == keyCode then
                setShown(not shown)
            end
        end))
        Collection.log(("hud: click amitoofast or press %s to hide"):format(keyName))
    else
        Collection.log("hud: unknown HUDKey " .. keyName .. " - click the brand instead")
    end

    _G.KaitunHUD = function(show)
        if show == nil then
            return setShown(not shown)
        end
        return setShown(show)
    end

    local function short(value)
        value = tonumber(value) or 0
        if value >= 1000000 then return ("%.1fM"):format(value / 1000000) end
        if value >= 1000 then return ("%.1fK"):format(value / 1000) end
        return tostring(math.floor(value))
    end

    local function slotData()
        local playerService = replicatedStorage:FindFirstChild("Player_Service")
        local dataFolder    = playerService and playerService:FindFirstChild("Data")
        local mine          = dataFolder and dataFolder:FindFirstChild(localPlayer.Name)
        local slotEquipped  = mine and mine:FindFirstChild("slotEquipped")
        local slots         = mine and mine:FindFirstChild("slots")
        return slots and slots:FindFirstChild("Slot" .. tostring(slotEquipped and slotEquipped.Value or 1))
    end

    local warned = {}
    local function try(what, fireFunction)
        local ok, err = pcall(fireFunction)
        if not ok and not warned[what] then
            warned[what] = true
            Collection.log(("hud: %s failed - %s"):format(what, tostring(err)))
        end
    end

    task.spawn(function()
        while Collection.alive() do
            raiseIdentity()

            try("status", function()
                local status = Collection.hudNote
                if status == nil then
                    status = Collection.state() .. (Collection.readied() and " (readied)" or "")
                end
                hud.state.Text = ("Status: %s   |   Hearts: %s   |   Cards: %d"):format(
                    status, tostring(Collection.hearts() or "-"), Collection.picks)
            end)

            try("money", function()
                local data = slotData()
                local wen  = data and data:FindFirstChild("Wen")
                local exp  = data and data:FindFirstChild("Exp")
                local goal = exp and exp:FindFirstChild("Goal")
                local per  = 60
                local okSettings, gameSettings = pcall(require, replicatedStorage.CAM.Global.gameSettings)
                if okSettings and type(gameSettings) == "table" and tonumber(gameSettings.expPerLevel) then
                    per = gameSettings.expPerLevel
                end
                local level = (goal ~= nil and per ~= 0) and math.floor(goal.Value / per) or 0
                raiseIdentity()
                hud.money.Text = ("%s  %s   |   Lv %d"):format(
                    utf8.char(128176), short(wen and wen.Value or 0), level)
            end)

            try("info", function()
                raiseIdentity()
                hud.info.Text = ("Ouwigahara   |   Combat: %s"):format(tostring(Collection.combatStatus or "-"))
            end)

            try("target", function()
                local held = Collection.held
                raiseIdentity()
                hud.timers.Text = ("Target: %s"):format(held ~= nil and held.Name or "-")
            end)

            task.wait(0.5)
        end
        pcall(function() gui:Destroy() end)
    end)

    Collection.log("hud: on screen")
end

_G.DgSet = function(key, value)
    Collection[key] = value
    return ("%s = %s"):format(tostring(key), tostring(value))
end

_G.DgGet = function()
    local enemy, dist = Collection.nearest()
    return ("cards=%s combat=%s reach=%s target=%s nearest=%s dist=%s route=%s status=%s"):format(
        tostring(Collection.cards), tostring(Collection.combat), tostring(Collection.reach),
        tostring(Collection.target),
        enemy and enemy.Name or "none",
        dist and ("%.0f"):format(dist) or "-",
        tostring(Collection.routeName), tostring(Collection.combatStatus))
        .. (" hearts=" .. tostring(Collection.hearts() or "-"))
end

_G.DgEquip = function()
    local ok, detail = Collection.drawWeapon()
    return ("drawn=%s ok=%s %s"):format(
        tostring(Collection.weaponDrawn()), tostring(ok), tostring(detail))
end

Collection.log(("running on %s - getgenv().Config.Enabled = false to stop"):format(
    game.PlaceId == 75556147183481 and "Ouwigahara"
    or game.PlaceId == 136406881576517 and "Ouwland" or tostring(game.PlaceId)))
