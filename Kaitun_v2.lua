local Collection = {}

Collection.DEFAULTS = {
    Enabled          = true,

    Farm             = true,
    Quests           = true,
    Loot             = true,
    LootChests       = true,
    LootRange        = 0,
    EquipBest        = true,
    AutoEquipWeapon  = true,
    Spin             = false,

    AutoPickQuest    = true,
    CombatQuestsOnly = true,
    AutoBreathing    = true,
    BreathingStyle   = nil,
    Quest            = nil,
    QuestPriority    = nil,
    QuestSkip        = nil,

    BehindStance     = "Behind",
    AvoidShield      = true,
    BackOffStuds     = 10,
    ComboBackoff     = true,
    ComboBackoffTime = 1.5,
    CycleTargets     = false,
    CycleInterval    = 0.5,
    Region           = "Windy Peak",
    Targets          = nil,
    TargetSkip       = nil,

    SpinUntilRarity  = 7,

    Weapon           = nil,
    WeaponSlot       = "One",

    AutoOuwland      = true,
    PrivateServerOwner = nil,

    Dungeon          = false,
    DungeonLevel     = 65,
    DungeonCards     = true,
    DungeonStance    = "Behind",

    BossFarm         = false,
    BossWeapons      = nil,
    BossKeepFarming  = false,
    BossIgnoreRace   = false,

    AntiIdle         = true,
    HUD              = true,
    HUDKey           = "RightShift",

    SkillTree        = true,
    SkillFocus       = "Balanced",
    SkillBudget      = nil,
    EquipMode        = "balanced",
    Diagnostic       = false,
    Verbose          = true,
    TravelCooldown   = 5,
}

Collection.ALIASES = {
    AutoFarm           = "Farm",
    AutoQuest          = "Quests",
    AutoQuests         = "Quests",
    AutoLoot           = "Loot",
    AutoChests         = "LootChests",
    AutoEquip          = "EquipBest",
    AutoSpin           = "Spin",
    AutoSkillTree      = "SkillTree",
    AutoTeleport       = "AutoOuwland",
    Stance             = "BehindStance",
    Private_Server_Owner = "PrivateServerOwner",
    PrivateOwner       = "PrivateServerOwner",
}

local globalEnv = (typeof(getgenv) == "function" and getgenv()) or _G

local config = globalEnv.Config or globalEnv.config or _G.config or {}

function Collection.globalString(name)
    local sources = { globalEnv, _G }
    for level = 1, 3 do
        local okEnv, env = pcall(getfenv, level)
        if okEnv and type(env) == "table" then
            table.insert(sources, env)
        end
    end

    for _, source in sources do
        local ok, value = pcall(function() return source[name] end)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
end

for _, name in { "Private_Server_Owner", "PrivateServerOwner" } do
    if config.PrivateServerOwner == nil then
        config.PrivateServerOwner = Collection.globalString(name)
    end
end

for alias, canonical in pairs(Collection.ALIASES) do
    if config[alias] ~= nil and config[canonical] == nil then
        config[canonical] = config[alias]
    end
end

for key, value in pairs(Collection.DEFAULTS) do
    if config[key] == nil then
        config[key] = value
    end
end

globalEnv.Config = config
_G.config = config

do
    local queue = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
        or (typeof(queueonteleport) == "function" and queueonteleport)
        or (typeof(syn) == "table" and syn.queue_on_teleport)

    if globalEnv.amitoofast_loader then
        if config.Verbose then
            print("[auto] requeue: handled by the loader")
        end
    elseif config.Requeue and queue ~= nil then
        local clear = (typeof(clear_teleport_queue) == "function" and clear_teleport_queue)
            or (typeof(clearteleportqueue) == "function" and clearteleportqueue)
            or (typeof(clearqueueonteleport) == "function" and clearqueueonteleport)
        if clear ~= nil then
            pcall(clear)
        end

        local parts = {}
        for key, value in pairs(config) do
            local kind = type(value)
            if kind == "string" then
                table.insert(parts, ("[%q]=%q"):format(key, value))
            elseif kind == "number" or kind == "boolean" then
                table.insert(parts, ("[%q]=%s"):format(key, tostring(value)))
            end
        end

        local function loaderFor(url, file, fallback)
            if type(url) == "string" and url ~= "" then
                return ("loadstring(game:HttpGet(%q))()"):format(url)
            end
            return ("loadstring(readfile(%q))()"):format(tostring(file or fallback))
        end

        local chunk = ("task.wait(6) getgenv().Config = {%s} if game.PlaceId == %d then %s else %s end")
            :format(table.concat(parts, ","), 75556147183481,
                loaderFor(config.DungeonUrl, config.DungeonFile, "Kaitun_Dungeon_v2.lua"),
                loaderFor(config.RequeueUrl, config.RequeueFile, "Kaitun_v2.lua"))

        local ok = pcall(queue, chunk)
        if config.Verbose then
            print("[auto] requeue:", ok and "armed for the next teleport"
                or "queue_on_teleport refused")
        end
    elseif config.Requeue and config.Verbose then
        print("[auto] requeue: executor has no queue_on_teleport"
            .. " - will not survive a teleport")
    end
end

if type(_G.__kaitunConns) == "table" then
    for _, connection in _G.__kaitunConns do
        pcall(function() connection:Disconnect() end)
    end
end
_G.__kaitunConns = {}

local RUN = {}
_G.__kaitunRun = RUN

function Collection.alive()
    return config.Enabled == true and _G.__kaitunRun == RUN
end

function Collection.track(connection)
    table.insert(_G.__kaitunConns, connection)
    return connection
end

local playersService    = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService        = game:GetService("RunService")
local workspaceService  = game:GetService("Workspace")

local localPlayer = playersService.LocalPlayer

task.spawn(function()
    local wired = nil

    while Collection.alive() do
        local ok, coreGui = pcall(game.GetService, game, "CoreGui")
        local node = ok and coreGui
            and coreGui:FindFirstChild("RobloxNetworkPauseNotification") or nil

        if node ~= nil then
            for _, child in node:GetChildren() do
                pcall(function() child:Destroy() end)
            end

            if wired ~= node then
                wired = node
                Collection.track(node.ChildAdded:Connect(function(child)
                    pcall(function() child:Destroy() end)
                end))
            end
        else
            wired = nil
        end

        task.wait(20)
    end
end)

function Collection.raiseIdentity()
    local setter = (typeof(setthreadidentity) == "function" and setthreadidentity)
        or (typeof(setidentity) == "function" and setidentity)
        or (typeof(syn) == "table" and syn.set_thread_identity)
        or (typeof(set_thread_identity) == "function" and set_thread_identity)

    if setter then
        pcall(setter, 8)
    end
end

Collection.raiseIdentity()

function Collection.log(...)
    if config.Verbose then
        print("[auto]", ...)
    end
end

function Collection.tryRequire(...)
    local node = replicatedStorage
    for _, name in { ... } do
        node = node and node:FindFirstChild(name)
    end
    if node == nil then return nil end
    local ok, loadedModule = pcall(require, node)
    return ok and loadedModule or nil
end

local Checker        = Collection.tryRequire("CAM", "Global", "Checker")
local Combat_presets = Collection.tryRequire("CAM", "Global", "Combat_presets")
local Items          = Collection.tryRequire("CAM", "Global", "Collectibles", "Items")
local Utility        = Collection.tryRequire("CAM", "Global", "Utility")
local QuestsModule   = Collection.tryRequire("CAM", "Global", "Subsets", "Gameplay", "Quests")
local DialogueModule = Collection.tryRequire("CAM", "Client", "Modules", "GamePlay", "Dialogue")
local ClansModule    = Collection.tryRequire("CAM", "Clans")

local Signals = replicatedStorage
    :WaitForChild("Communication")
    :WaitForChild("ServerAndClient")
    :WaitForChild("Signals")

local Event       = Signals:WaitForChild("SignalEvent"):WaitForChild("Event")
local SpinFunction = Signals:WaitForChild("SignalFunction"):WaitForChild("Function")

function Collection.activeSlot(slots, mine)
    local equipped = mine and mine:FindFirstChild("slotEquipped")
    if equipped ~= nil and slots ~= nil then
        local named = slots:FindFirstChild("Slot" .. tostring(math.floor(equipped.Value)))
        if named ~= nil and named:FindFirstChild("Inventory") ~= nil then
            return named
        end
    end

    for _, slot in (slots and slots:GetChildren() or {}) do
        if slot:FindFirstChild("Inventory") ~= nil then
            return slot
        end
    end
end

function Collection.playerData()
    if Utility ~= nil and type(Utility.GetData) == "function" then
        local ok, data = pcall(Utility.GetData, localPlayer)
        if ok and data ~= nil then return data end
    end

    local service    = replicatedStorage:FindFirstChild("Player_Service")
    local dataFolder = service and service:FindFirstChild("Data")
    local mine       = dataFolder and dataFolder:FindFirstChild(localPlayer.Name)
    local slots      = mine and mine:FindFirstChild("slots")
    return Collection.activeSlot(slots, mine)
end

function Collection.myRoot()
    local playerCharacter = localPlayer.Character
    local playerHumanoid  = playerCharacter
        and playerCharacter:FindFirstChildOfClass("Humanoid")
    if playerHumanoid == nil or playerHumanoid.Health <= 0 then return nil end
    return playerCharacter:FindFirstChild("HumanoidRootPart")
end

function Collection.teleportTo(pos)
    local rootPart = Collection.myRoot()
    if rootPart == nil or pos == nil then return false end
    rootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 4))
    rootPart.AssemblyLinearVelocity  = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    return true
end

Collection.playerScripts = localPlayer:WaitForChild("PlayerScripts", 20)
Collection.clientRoot    = Collection.playerScripts and Collection.playerScripts:WaitForChild("CU", 10)
Collection.combatScript  = Collection.clientRoot and Collection.clientRoot:FindFirstChild("Combat")
Collection.ComboValue    = Collection.combatScript and Collection.combatScript:FindFirstChild("ComboValue")

Collection.punchFails = 0

function Collection.routeName()
    return Collection.route == 1 and "punch(getsenv)" or Collection.route == 2 and "Do(require)" or "raw remote"
end

function Collection.resolveRoute()
    local before = Collection.route
    Collection.punch, Collection.Do = nil, nil

    local scriptsFolder = localPlayer:FindFirstChild("PlayerScripts")
    local clientFolder = scriptsFolder and scriptsFolder:FindFirstChild("CU")
    Collection.combatScript = clientFolder and clientFolder:FindFirstChild("Combat") or nil
    Collection.ComboValue   = Collection.combatScript and Collection.combatScript:FindFirstChild("ComboValue") or nil

    if Collection.combatScript ~= nil then
        if typeof(getsenv) == "function" then
            local ok, env = pcall(getsenv, Collection.combatScript)
            if ok and type(env) == "table" and type(rawget(env, "punch")) == "function" then
                Collection.punch = rawget(env, "punch")
            end
        end
        local combatModule = Collection.combatScript:FindFirstChild("Main_Combat_Script_Client")
        if combatModule then
            local ok, loadedModule = pcall(require, combatModule)
            if ok and type(loadedModule) == "table" and type(loadedModule.Do) == "function" then Collection.Do = loadedModule.Do end
        end
    end

    Collection.route = Collection.punch and 1 or Collection.Do and 2 or 3
    Collection.punchFails = 0
    if Collection.route ~= before then
        Collection.log("combat route:", Collection.routeName())
    end
    return Collection.route
end

Collection.resolveRoute()

function Collection.presetFromTools()
    if Combat_presets == nil then return nil end

    local humanoids = workspaceService:FindFirstChild("Humanoids")
    local playerCharacter = (humanoids and humanoids:FindFirstChild(localPlayer.Name)) or localPlayer.Character
    local tools = playerCharacter and playerCharacter:FindFirstChild("Tool_Accessories")

    local toolModels = tools and tools:GetChildren() or {}
    if #toolModels == 0 then
        return Combat_presets.Presets["Combat"] and "Combat" or nil
    end

    local function presetFor(name)
        if Combat_presets.Presets[name] then
            return name
        end
        local item = Items and Items[name]
        local mapped = item and item.CombatPreset
        if mapped and Combat_presets.Presets[mapped] then
            return mapped
        end
    end

    for _, model in toolModels do
        if not string.find(model.Name, "Sheathed") then
            local found = presetFor(model.Name)
            if found then return found end
        end
    end

    for _, model in toolModels do
        local found = presetFor((string.gsub(model.Name, "Sheathed%d*$", "")))
        if found then return found end
    end
end

Collection.lastPunch, Collection.lastCombovalue = 0, 0

function Collection.gapFor(preset)
    local maxCombo = preset.Max or 5
    local gap = preset.default or 0.25
    local current = Collection.ComboValue and Collection.ComboValue.Value or 1
    if Collection.lastCombovalue >= maxCombo and current < maxCombo then
        gap = preset.final or gap
    end
    return gap
end

function Collection.combatStep()
    local presetName = Collection.presetFromTools()
    local preset = presetName and Combat_presets.Presets[presetName]
    if preset == nil or Collection.ComboValue == nil then
        return nil, "nothing equipped"
    end

    local gap, since = Collection.gapFor(preset), os.clock() - Collection.lastPunch
    if gap >= since then return gap - since, "cooldown" end

    if Checker ~= nil and Checker.check(localPlayer, "combat") ~= true then
        return nil, "blocked by Checker"
    end

    local maxCombo, value = preset.Max or 5, Collection.ComboValue.Value

    if Collection.route == 2 then
        local ok, result = pcall(Collection.Do, Collection.ComboValue, preset, presetName, nil)
        if not ok then return nil, "Do error" end
        Collection.lastCombovalue = (type(result) == "table" and result.combovalue) or value
    else
        local beforeSwing = (preset.delay_before_swing and preset.delay_before_swing[value])
            or preset.default_before_swing or Combat_presets.Default_Swing_Wait or 0
        local beforeHit = (preset.delay_before_hit and preset.delay_before_hit[value])
            or preset.default_before_hit or beforeSwing
        local speedMultiplier = 1
        if type(Combat_presets.attackSpeedMult) == "function" then
            local okMult, multiplier = pcall(Combat_presets.attackSpeedMult, localPlayer)
            if okMult and type(multiplier) == "number" and multiplier > 0 then speedMultiplier = multiplier end
        end
        pcall(function()
            Event:FireServer("Combat_Service", presetName, value, false,
                (beforeHit - beforeSwing) / speedMultiplier, false, nil)
        end)
        Collection.lastCombovalue = value
    end

    Combat_presets.Last_Combo = value
    Collection.ComboValue.Value = (value == maxCombo or value == 7) and 1 or value + 1
    Collection.lastPunch = os.clock()
    return Collection.gapFor(preset), "punching " .. presetName
end

Collection.target, Collection.targetRoot, Collection.targetShielded = nil, nil, false
Collection.targetName = "-"
Collection.behindTargets = {}
Collection.lastRetarget = 0


Collection.targetSkip = { ["Civilian"] = true, ["*Civilian*"] = true }
for name in pairs(config.TargetSkip or {}) do
    Collection.targetSkip[name] = true
end


Collection.unpaidKills = {}
Collection.rewardExp, Collection.rewardWen = 0, 0
Collection.rewardStart = 0

function Collection.expWen()
    local data       = Collection.playerData()
    local expFolder  = data and data:FindFirstChild("Exp")
    local currentExp = expFolder and expFolder:FindFirstChild("Current")
    local wenValue   = data and data:FindFirstChild("Wen")
    return (currentExp and currentExp.Value or 0), (wenValue and wenValue.Value or 0)
end

function Collection.scoreKill(model, name)
    if name == nil then return end

    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    local dead = model ~= nil and model.Parent ~= nil and humanoid ~= nil and humanoid.Health <= 0
    if not dead then return end

    local wasExp, wasWen = Collection.rewardExp, Collection.rewardWen
    task.delay(2, function()
        local nowExp, nowWen = Collection.expWen()
        if nowExp ~= wasExp or nowWen > wasWen then
            Collection.unpaidKills[name] = 0
        else
            local unpaid = (Collection.unpaidKills[name] or 0) + 1
            Collection.unpaidKills[name] = unpaid
            if unpaid >= 3 and not Collection.targetSkip[name] then
                Collection.targetSkip[name] = true
                Collection.log(("skipping %s - %d kills, no exp or wen"):format(name, unpaid))
            end
        end
    end)
end

Collection.comboBackoffUntil = 0

function Collection.hookComboTracker()
    local service = replicatedStorage:FindFirstChild("Player_Service")
    local values = service and service:FindFirstChild("Values")
    local mine = values and values:FindFirstChild(localPlayer.Name)
    if mine == nil then return end

    local function bind(tracker)
        if not tracker:IsA("IntValue") then return end
        Collection.track(tracker.Changed:Connect(function(value)
            if config.ComboBackoff and value >= 5 then
                Collection.comboBackoffUntil = os.clock() + (config.ComboBackoffTime or 1.5)
            end
        end))
    end

    local existing = mine:FindFirstChild("ComboTrackerClient")
    if existing then
        bind(existing)
    else
        Collection.track(mine.ChildAdded:Connect(function(child)
            if child.Name == "ComboTrackerClient" then bind(child) end
        end))
    end
end

task.spawn(Collection.hookComboTracker)

function Collection.npcFolders()
    local found = {}
    for _, region in (function()
        local humanoids = workspaceService:FindFirstChild("Humanoids")
        local regions = humanoids and humanoids:FindFirstChild("Regions")
        return regions and regions:GetChildren() or {}
    end)() do
        local activeNpcs = region:FindFirstChild("ActiveNpcs")
        if activeNpcs ~= nil and #activeNpcs:GetChildren() > 0 then
            table.insert(found, activeNpcs)
        end
    end
    return found
end

function Collection.normalise(text)
    return (string.gsub(string.lower(tostring(text)), "[^%a%d]", ""))
end

function Collection.isShielded(model)
    if model == nil then return false end
    local overHead = model:FindFirstChild("OverHead", true)
    local holder = overHead and overHead:FindFirstChild("Holder")
    return holder ~= nil and holder:FindFirstChild("Frame") ~= nil
end

function Collection.pickTarget()
    local rootPart = Collection.myRoot()
    if rootPart == nil then return nil end

    local wanted = config.Targets or Collection.behindTargets
    local best, bestDist, bestRoot
    local altTarget, altDist, altRoot

    for _, active in Collection.npcFolders() do
        for _, folder in active:GetChildren() do
            local named = (wanted ~= nil) and (wanted[folder.Name] == true)
            local match = named or
                ((wanted == nil or next(wanted) == nil) and not Collection.targetSkip[folder.Name])
            if folder:IsA("Folder") and match then
                local model = folder:FindFirstChild(folder.Name)
                if model and model:IsA("Model") then
                    local humanoid = model:FindFirstChildOfClass("Humanoid")
                    local npcRoot  = model:FindFirstChild("HumanoidRootPart")
                    if humanoid and npcRoot and humanoid.Health > 0 then
                        local distance = (npcRoot.Position - rootPart.Position).Magnitude
                        if config.CycleTargets and config.AvoidShield and Collection.isShielded(model) then
                            if altDist == nil or distance < altDist then
                                altTarget, altDist, altRoot = model, distance, npcRoot
                            end
                        elseif bestDist == nil or distance < bestDist then
                            best, bestDist, bestRoot = model, distance, npcRoot
                        end
                    end
                end
            end
        end
    end

    if best == nil then
        return altTarget, altRoot
    end
    return best, bestRoot
end

Collection.questTravel = false

function Collection.targetValid()
    if Collection.target == nil or Collection.targetRoot == nil then return false end
    if Collection.target.Parent == nil or Collection.targetRoot.Parent == nil then return false end
    local humanoid = Collection.target:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

function Collection.nearestWanted()
    local rootPart = Collection.myRoot()
    if rootPart == nil then return nil end

    local wanted = config.Targets
    local named = wanted ~= nil and next(wanted) ~= nil

    local bestPos, bestDist, bestName
    for _, active in Collection.npcFolders() do
        for _, folder in active:GetChildren() do
            local ok
            if named then
                ok = wanted[folder.Name] == true
            else
                ok = not Collection.targetSkip[folder.Name]
            end

            if ok then
                for _, model in folder:GetChildren() do
                    local humanoid = model:FindFirstChildOfClass("Humanoid")
                    local npcRoot  = model:FindFirstChild("HumanoidRootPart")
                    if humanoid ~= nil and npcRoot ~= nil and humanoid.Health > 0 then
                        local distance = (npcRoot.Position - rootPart.Position).Magnitude
                        if bestDist == nil or distance < bestDist then
                            bestPos, bestDist, bestName = npcRoot.Position, distance, folder.Name
                        end
                    end
                end
            end
        end
    end

    return bestPos, bestDist, bestName
end

Collection.track(runService.Heartbeat:Connect(function()
    if not (config.Enabled and config.Farm) then return end
    if Collection.questTravel then return end

    local rootPart = Collection.myRoot()
    if rootPart == nil then
        Collection.target, Collection.targetRoot, Collection.targetShielded = nil, nil, false
        return
    end

    local stale = config.CycleTargets and (os.clock() - Collection.lastRetarget) > (config.CycleInterval or 0.5)

    local named = (config.Targets or Collection.behindTargets)
    named = Collection.rewardName ~= nil and named ~= nil and named[Collection.rewardName] == true
    local timedOut = Collection.rewardName ~= nil and not named
        and Collection.targetValid() and (os.clock() - Collection.rewardStart) > 15

    if timedOut then
        Collection.targetSkip[Collection.rewardName] = true
        Collection.log(("skipping %s - still alive after %ds"):format(Collection.rewardName, 15))
        Collection.target, Collection.targetRoot = nil, nil
        Collection.targetName = "-"
    end

    if not Collection.targetValid() or stale then
        local oldTarget, oldName = Collection.target, Collection.rewardName
        local newTarget, newRoot = Collection.pickTarget()
        if newTarget ~= nil then
            Collection.target, Collection.targetRoot = newTarget, newRoot
            Collection.targetName = newTarget and newTarget.Name or "-"
            Collection.lastRetarget = os.clock()
        elseif not Collection.targetValid() then
            Collection.target, Collection.targetRoot = nil, nil
            Collection.targetName = "-"
            Collection.targetShielded = false
            return
        end

        if Collection.target ~= oldTarget then
            Collection.scoreKill(oldTarget, oldName)
            Collection.rewardName = Collection.target and Collection.target.Name or nil
            Collection.rewardExp, Collection.rewardWen = Collection.expWen()
            Collection.rewardStart = os.clock()
        end
    end

    Collection.targetShielded = config.AvoidShield and Collection.isShielded(Collection.target) or false
    local comboResting = os.clock() < Collection.comboBackoffUntil

    local dist = 3.5
        + (Collection.targetShielded and config.BackOffStuds or 0)
        + (comboResting and 14 or 0)

    local spot
    if config.BehindStance == "Over" then
        spot = Collection.targetRoot.CFrame * CFrame.new(0, dist, 0)
    elseif config.BehindStance == "Under" then
        spot = Collection.targetRoot.CFrame * CFrame.new(0, -dist, 0)
    else
        spot = Collection.targetRoot.CFrame * CFrame.new(0, 0, dist)
    end

    local upVector = Collection.targetRoot.CFrame.UpVector
    local lookDirection = Collection.targetRoot.Position - spot.Position
    if lookDirection.Magnitude < 0.05 then
        lookDirection = Collection.targetRoot.CFrame.LookVector
    end
    if math.abs(lookDirection.Unit:Dot(upVector)) > 0.99 then
        upVector = Collection.targetRoot.CFrame.LookVector
    end
    rootPart.CFrame = CFrame.lookAt(spot.Position, spot.Position + lookDirection, upVector)

    rootPart.AssemblyLinearVelocity  = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
end))

function Collection.questsFolder()
    local data = Collection.playerData()
    return data and data:FindFirstChild("Quests") or nil
end

function Collection.activeQuestCount()
    local questFolder = Collection.questsFolder()
    local holder = questFolder and questFolder:FindFirstChild("Holder")
    return holder and #holder:GetChildren() or 0
end

function Collection.questCooldownLeft()
    local questFolder = Collection.questsFolder()
    local lastTime = questFolder and questFolder:FindFirstChild("LastTime")
    local cooldown = (QuestsModule and QuestsModule.QuestCD) or 30
    if lastTime == nil or lastTime.Value <= 0 then return 0 end
    local elapsed = os.time() - lastTime.Value
    if elapsed < 0 or elapsed > 86400 then return 0 end
    return math.max(0, cooldown - elapsed)
end

function Collection.questDef(key)
    return QuestsModule and type(QuestsModule.Holder) == "table"
        and QuestsModule.Holder[key] or nil
end

function Collection.findGiver(name)
    if name == nil then return nil end
    local debree = workspaceService:FindFirstChild("Debree")
    local regions = debree and debree:FindFirstChild("Regions")
    for _, region in (regions and regions:GetChildren() or {}) do
        local stationaryNpcs = region:FindFirstChild("StationaryNpcs")
        local npc = stationaryNpcs and stationaryNpcs:FindFirstChild(name)
        if npc then
            local part = npc:IsA("Model") and (npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart"))
                or (npc:IsA("BasePart") and npc)
            if part then return part.Position end

            local ok, pivot = pcall(function() return npc:GetPivot() end)
            if ok and pivot then return pivot.Position end
        end
    end
end

function Collection.findNpcAnywhere(name)
    if name == nil then return nil end
    local humanoids = workspaceService:FindFirstChild("Humanoids")
    local regions = humanoids and humanoids:FindFirstChild("Regions")
    for _, region in (regions and regions:GetChildren() or {}) do
        local activeNpcs = region:FindFirstChild("ActiveNpcs")
        local hit = activeNpcs and activeNpcs:FindFirstChild(name)
        local model = hit and hit:FindFirstChild(hit.Name)
        local part = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if part then return part.Position end
    end
    return Collection.findGiver(name)
end

function Collection.questWaypoint(key)
    local questDefinition = Collection.questDef(key)
    if questDefinition == nil then return nil end

    if typeof(questDefinition.Position) == "Vector3" then return questDefinition.Position end

    local markers = questDefinition.Markers
    if type(markers) == "table" then
        for _, marker in pairs(markers) do
            if type(marker) == "table" and typeof(marker.Position) == "Vector3" then
                return marker.Position
            end
        end
        for _, marker in pairs(markers) do
            if type(marker) == "table" and type(marker.Npc) == "string" then
                local pos = Collection.findNpcAnywhere(marker.Npc)
                if pos then return pos end
            end
        end
    end
end

function Collection.acceptKeyFor(displayName)
    if QuestsModule == nil or type(QuestsModule.Holder) ~= "table" then return nil end
    for key, questDefinition in pairs(QuestsModule.Holder) do
        if key == displayName then return key end
        local inst = questDefinition and questDefinition.QuestInstance
        if typeof(inst) == "Instance" and inst.Name == displayName then return key end
    end
end

function Collection.activeQuestKey()
    local questFolder = Collection.questsFolder()
    local holder = questFolder and questFolder:FindFirstChild("Holder")
    for _, quest in (holder and holder:GetChildren() or {}) do
        return Collection.acceptKeyFor(quest.Name), quest.Name
    end
end

function Collection.allTasksComplete()
    local questFolder = Collection.questsFolder()
    local holder = questFolder and questFolder:FindFirstChild("Holder")
    local hasTasks, done = false, true
    for _, quest in (holder and holder:GetChildren() or {}) do
        local tasks = quest:FindFirstChild("Tasks")
        for _, questTask in (tasks and tasks:GetChildren() or {}) do
            hasTasks = true
            local currentValue, maxValue = questTask:FindFirstChild("Value"), questTask:FindFirstChild("Max")
            if not (currentValue and maxValue and maxValue.Value > 0 and currentValue.Value >= maxValue.Value) then done = false end
        end
    end
    return hasTasks and done
end

Collection.CODE_OVERRIDES = { VillageSpy = { "*Civilian*" } }

function Collection.resolveQuestTargets()
    local questFolder = Collection.questsFolder()
    local holder = questFolder and questFolder:FindFirstChild("Holder")
    local codes, questName = {}, ""
    for _, quest in (holder and holder:GetChildren() or {}) do
        questName = quest.Name
        local tasks = quest:FindFirstChild("Tasks")
        for _, questTask in (tasks and tasks:GetChildren() or {}) do
            local codeValue, currentValue, maxValue = questTask:FindFirstChild("Code"), questTask:FindFirstChild("Value"), questTask:FindFirstChild("Max")
            local finished = currentValue and maxValue and maxValue.Value > 0 and currentValue.Value >= maxValue.Value
            if codeValue and codeValue.Value ~= "" and not finished then table.insert(codes, codeValue.Value) end
        end
    end
    if #codes == 0 then return {} end

    local present = {}
    for _, active in Collection.npcFolders() do
        for _, folder in active:GetChildren() do
            if folder:IsA("Folder") then present[folder.Name] = true end
        end
    end
    if next(present) == nil then return {} end

    local flatQuest = Collection.normalise(questName)
    local picked = {}

    for _, code in codes do
        local flatCode = Collection.normalise(code)
        local hit = {}

        if present[code] then
            hit[code] = true
        end

        if next(hit) == nil then
            for _, candidate in (Collection.CODE_OVERRIDES[code] or {}) do
                if present[candidate] then hit[candidate] = true end
            end
        end

        if next(hit) == nil then
            for candidate in pairs(present) do
                if Collection.normalise(candidate) == flatCode then hit[candidate] = true end
            end
        end

        if next(hit) == nil then
            local bestName, bestScore
            for pass = 1, 2 do
                for candidate in pairs(present) do
                    local flat = Collection.normalise(candidate)
                    local match
                    if pass == 1 then
                        match = #flat > 2 and string.find(flat, flatCode, 1, true) ~= nil
                    else
                        match = #flat > 2 and string.find(flatCode, flat, 1, true) ~= nil
                    end

                    if match then
                        local score = #flat
                        if string.find(flatQuest, flat, 1, true) then
                            score = score + 1000
                        end
                        if bestScore == nil or score > bestScore then
                            bestName, bestScore = candidate, score
                        end
                    end
                end
                if bestName ~= nil then
                    break
                end
            end
            if bestName ~= nil then
                hit[bestName] = true
            end
        end

        for candidate in pairs(hit) do
            picked[candidate] = true
        end
    end

    if next(picked) == nil then
        for candidate in pairs(present) do
            if string.match(candidate, "^%*.+%*$") then picked[candidate] = true end
        end
    end

    return picked
end

function Collection.acceptQuest(key)
    local addQuest = DialogueModule and DialogueModule.Functions and DialogueModule.Functions.AddQuest
    if type(addQuest) ~= "function" then return false, "NoAddQuestFunction" end
    local ok, reason = pcall(addQuest, key)
    if not ok then return false, tostring(reason) end
    if reason ~= nil then return false, tostring(reason) end
    return true
end

Collection.QUEST_SKIP = { ["Ill help clear them out"] = true }

Collection.BOSS_QUESTS = {
    ["Ill take the bandit boss(Lv 7)"]  = "Zuko",
    ["Ill fell the Mother Bear(Lv 18)"] = "Mother Bear",
    ["Ill deal with Kaiden(Lv 34)"]     = "Kaiden",
    ["I will take care of Hoyuzo(Lv 50)"] = "Hoyuzo",
}

function Collection.abandonQuest(displayName)
    if type(displayName) ~= "string" or displayName == "" then
        return false, "no quest to drop"
    end

    local before = Collection.activeQuestCount()
    pcall(function() Event:FireServer("RemoveQuest", displayName) end)

    local deadline = os.clock() + 3
    repeat
        task.wait(0.2)
    until Collection.activeQuestCount() < before or os.clock() > deadline

    if Collection.activeQuestCount() < before then
        return true, "dropped " .. displayName
    end
    return false, "server kept " .. displayName
end

function Collection.bossSpawned(questKey)
    local name = Collection.BOSS_QUESTS[questKey]
    if name == nil then
        return true
    end

    local humanoids = workspaceService:FindFirstChild("Humanoids")
    local regions = humanoids and humanoids:FindFirstChild("Regions")
    for _, region in (regions and regions:GetChildren() or {}) do
        local active = region:FindFirstChild("ActiveNpcs")
        local folder = active and active:FindFirstChild(name)
        for _, model in (folder and folder:GetChildren() or {}) do
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if humanoid ~= nil and humanoid.Health > 0 then
                return true
            end
        end
    end
    return false
end

Collection.QUEST_PRIORITY = {
    "Ill take 3 bandits",
    "Ill take the bandit boss(Lv 7)",
    "Ill drive the bears back(Lv 10)",
    "Ill fell the Mother Bear(Lv 18)",
    "Ill clear out his subordinates(Lv 26)",
    "Ill deal with Kaiden(Lv 34)",
    "I will clear out his guards(Lv 40)",
    "Ill drive them off(Lv 47)",
    "I will take care of Hoyuzo(Lv 50)",
    "Ill clear the cave(Lv 62)",
    "Ill eliminate the Mizunoto(Lv 62)",
    "Ill learn the Soryu Style(Lv 62)",
    "Ill learn the Tai Chi Style(Lv 65)",
    "Ill break their watch(Lv 75)",
    "Ill thin them out(Lv 75)",
    "Ill go up after the greater ones(Lv 83)",
    "Ill help you defeat them(Lv 90)",
    "Theyre not welcome here(Lv 90)",
    "Ill learn the Reaping Blades Style(Lv 100)",
    "Ill drive back the frost(Lv 105)",
    "Ill see you to Windy Peak(Lv 105)",
    "Ill put out the blaze(Lv 115)",
}

function Collection.questPlan()
    local key = config.CombatQuestsOnly and "combat" or "all"
    if Collection.questPlanCache and Collection.questPlanKey == key then return Collection.questPlanCache end

    local list = {}
    for rawKey, questDefinition in pairs((QuestsModule and QuestsModule.Holder) or {}) do
        local key = rawKey
        local category = tostring(questDefinition.Category or "")
        local giver = type(questDefinition.OfferNpc) == "string" and questDefinition.OfferNpc or nil
        local wanted = (category ~= "BossHunt" and category ~= "Muzan")
            and not (type(config.QuestSkip) == "table" and config.QuestSkip or Collection.QUEST_SKIP)[key]
            and (not config.CombatQuestsOnly or category == "Combat")
        if giver and wanted then
            table.insert(list, {
                key = key,
                level = tonumber(string.match(key, "%(Lv (%d+)%)")) or 0,
                giver = giver,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.key < b.key
    end)

    Collection.questPlanCache = list
    Collection.questPlanKey = config.CombatQuestsOnly and "combat" or "all"
    return list
end

function Collection.playerLevel()
    local data = Collection.playerData()
    local expFolder = data and data:FindFirstChild("Exp")
    local goal = expFolder and expFolder:FindFirstChild("Goal")
    local expPerLevel = 60
    local okSettings, gameSettings = pcall(require, replicatedStorage.CAM.Global.gameSettings)
    if okSettings and type(gameSettings) == "table" and tonumber(gameSettings.expPerLevel) then
        expPerLevel = gameSettings.expPerLevel
    end
    if goal == nil or expPerLevel == 0 then
        return 0
    end
    return math.floor(goal.Value / expPerLevel)
end

function Collection.hasBreathing()
    local data = Collection.playerData()
    local powers = data and data:FindFirstChild("Powers")
    local breathing = powers and powers:FindFirstChild("Breathing")
    return breathing ~= nil and tostring(breathing.Value) ~= ""
end

Collection.BREATHING_STYLES = {
    "Serpent", "Wind", "Insect", "Sound", "Stone", "Water", "Flame", "Thunder",
}

function Collection.breathingQuestKey(style)
    if style == nil or style == "" then
        return nil
    end
    return ("Ill learn %s Breathing(Lv 25)"):format(style)
end

function Collection.questCost(key)
    local questDefinition = QuestsModule and QuestsModule.Holder and QuestsModule.Holder[key]
    if questDefinition == nil then
        return nil
    end
    return questDefinition.WenCostOnAccept, questDefinition.ItemCostOnAccept
end

function Collection.canAfford(key)
    local wenCost, itemCost = Collection.questCost(key)
    if wenCost == nil and itemCost == nil then
        return true
    end

    local data = Collection.playerData()
    if data == nil then
        return false, "no player data"
    end

    if wenCost ~= nil then
        local wenValue = data:FindFirstChild("Wen")
        local have = wenValue and wenValue.Value or 0
        if have < wenCost then
            return false, ("need %d Wen, have %d"):format(wenCost, have)
        end
    end

    if type(itemCost) == "table" then
        local have = {}
        local inventory = data:FindFirstChild("Inventory")
        local inner = inventory and inventory:FindFirstChild("Inventory")
        for _, item in (inner and inner:GetChildren() or {}) do
            local amount = item:FindFirstChild("Amount")
            have[item.Name] = (have[item.Name] or 0) + (amount and amount.Value or 1)
        end

        for itemName, need in pairs(itemCost) do
            if (have[itemName] or 0) < need then
                return false, ("need %dx %s, have %d"):format(need, tostring(itemName), have[itemName] or 0)
            end
        end
    end

    return true
end

function Collection.breathingWanted()
    if not config.AutoBreathing then return nil end
    if Collection.playerLevel() < 25 or Collection.hasBreathing() then return nil end
    if QuestsModule == nil or type(QuestsModule.Holder) ~= "table" then return nil end

    local order = {}
    if config.BreathingStyle ~= nil then
        table.insert(order, config.BreathingStyle)
    else
        for _, style in Collection.BREATHING_STYLES do
            table.insert(order, style)
        end
    end

    for _, style in order do
        local key = Collection.breathingQuestKey(style)
        if key ~= nil and QuestsModule.Holder[key] ~= nil then
            local afford, why = Collection.canAfford(key)
            if afford then
                return key
            end
        end
    end
end

function Collection.questUsable(key)
    if key == nil or QuestsModule == nil or type(QuestsModule.CanAddQuest) ~= "function" then
        return false
    end
    local questDefinition = QuestsModule.Holder and QuestsModule.Holder[key]
    if questDefinition == nil then
        return false
    end
    local good, allowed = pcall(QuestsModule.CanAddQuest, key)
    if not (good and allowed) then
        return false
    end
    local giver = type(questDefinition.OfferNpc) == "string" and questDefinition.OfferNpc or nil
    if giver == nil then
        return false
    end

    if Collection.findGiver(giver) ~= nil then
        return true, giver
    end
    if typeof(questDefinition.Position) == "Vector3" then
        return true, giver, questDefinition.Position
    end

    if type(questDefinition.Markers) == "table" then
        local names = {}
        for name in pairs(questDefinition.Markers) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in names do
            local marker = questDefinition.Markers[name]
            if type(marker) == "table" and typeof(marker.Position) == "Vector3" then
                return true, giver, marker.Position
            end
        end
    end
    return false
end

Collection.farmQuestSkip = {}

Collection.ITEM_FARM = {
    ["Demon Horns"] = {
        targets  = { ["Hoyuzo"] = true, ["Hoyuzo Subordinate"] = true },
        position = Vector3.new(651, 1001, -1023),
        quests   = {
            "I will clear out his guards(Lv 40)",
            "I will take care of Hoyuzo(Lv 50)",
        },
    },
    ["Beast Core"] = {
        targets  = { ["Beast Born Demon"] = true },
        position = Vector3.new(171, 889, 604),
        quests   = { "Ill drive them off(Lv 47)" },
    },
}

function Collection.itemCount(itemName)
    local data = Collection.playerData()
    local inventory = data and data:FindFirstChild("Inventory")
    local inner = inventory and inventory:FindFirstChild("Inventory")
    local total = 0
    for _, item in (inner and inner:GetChildren() or {}) do
        if item.Name == itemName then
            local amount = item:FindFirstChild("Amount")
            total = total + (amount and amount.Value or 1)
        end
    end
    return total
end

function Collection.breathingItemGap(style)
    local key = Collection.breathingQuestKey(style)
    local _, itemCost = Collection.questCost(key)
    if type(itemCost) ~= "table" then
        return nil
    end

    for itemName, need in pairs(itemCost) do
        if Collection.ITEM_FARM[itemName] then
            local have = Collection.itemCount(itemName)
            if have < need then
                return itemName, need, have
            end
        end
    end
end

function Collection.nextEligibleQuest()
    if QuestsModule == nil or type(QuestsModule.CanAddQuest) ~= "function" then
        return nil
    end

    local usable = Collection.questUsable

    if config.AutoBreathing and Collection.playerLevel() >= 25 and not Collection.hasBreathing() then
        local order = {}
        if config.BreathingStyle ~= nil then
            table.insert(order, config.BreathingStyle)
        else
            for _, style in Collection.BREATHING_STYLES do
                table.insert(order, style)
            end
        end

        for _, style in order do
            local key = Collection.breathingQuestKey(style)
            local fine, giver = usable(key)
            if fine then
                local afford, why = Collection.canAfford(key)
                if afford then
                    return key, giver
                end
            end
        end
    end

    local chain = type(config.QuestPriority) == "table" and config.QuestPriority or Collection.QUEST_PRIORITY
    local skip  = type(config.QuestSkip) == "table" and config.QuestSkip or Collection.QUEST_SKIP
    local owedTraining = config.AutoBreathing and Collection.playerLevel() >= 25 and not Collection.hasBreathing()

    local bestKey, bestGiver, bestTravel
    for _, key in chain do
        local bossBlocked = Collection.BOSS_QUESTS[key] ~= nil
            and (owedTraining or not Collection.bossSpawned(key))
        if not skip[key] and not bossBlocked then
            local fine, giver, travelTo = usable(key)
            if fine then
                bestKey, bestGiver, bestTravel = key, giver, travelTo
            end
        end
    end
    if bestKey ~= nil then
        return bestKey, bestGiver, bestTravel
    end

    for _, entry in Collection.questPlan() do
        if Collection.BOSS_QUESTS[entry.key] ~= nil
            and (owedTraining or not Collection.bossSpawned(entry.key)) then
        else
            local fine, giver = usable(entry.key)
            if fine then
                return entry.key, giver
            end
        end
    end
end

function Collection.fireProx(prompt)
    local fireFunction = (typeof(fireproximityprompt) == "function" and fireproximityprompt)
        or (typeof(fireprox) == "function" and fireprox)
        or (typeof(syn) == "table" and syn.fireproximityprompt)
    if fireFunction then return pcall(fireFunction, prompt) end
    return pcall(function()
        local hold = prompt.HoldDuration
        prompt.HoldDuration = 0
        prompt:InputHoldBegin()
        prompt:InputHoldEnd()
        prompt.HoldDuration = hold
    end)
end

Collection.TRAINING_FOLDER = {
    ["Meditation"]      = "Meditation",
    ["Pushups"]         = "Pushups",
    ["Boulder Split"]   = "Boulder Split",
    ["Target Shooting"] = "Aim Training",
    ["Cup Game"]        = "Cup Game",
    ["Squat"]           = "Squat Rack",
    ["Boulder Push"]    = "Boulder Push",
    ["Parkour Dungeon"] = "Parkour Dungeon",
}

Collection.TRAINING_OVERRIDE = {
    ["Target Shooting"] = Vector3.new(-1496, 315, -159),
}

function Collection.trainingMarker(code)
    local ok, gameSettings = pcall(require, replicatedStorage.CAM.Global.gameSettings)
    if not ok or type(gameSettings) ~= "table" then return nil end
    local markerPositions = gameSettings.TrainingMarkerPositions
    local markerSet = markerPositions and (markerPositions[game.PlaceId] or markerPositions.Default)
    local entry = markerSet and markerSet[code]
    return entry and typeof(entry.Position) == "Vector3" and entry.Position or nil
end

function Collection.trainingSpots(code)
    local spots = {}

    local fixed = Collection.TRAINING_OVERRIDE[code]
    if fixed ~= nil then
        table.insert(spots, { pos = fixed, model = nil })
    end
    local training = workspaceService:FindFirstChild("Training")
    local folder = training and Collection.TRAINING_FOLDER[code]
        and training:FindFirstChild(Collection.TRAINING_FOLDER[code])

    for _, mat in (folder and folder:GetChildren() or {}) do
        if mat:IsA("Model") and mat.Name ~= "Sign" then
            local good, pivot = pcall(function() return mat:GetPivot() end)
            if good and mat:FindFirstChildWhichIsA("ProximityPrompt", true) then
                table.insert(spots, { pos = pivot.Position, model = mat })
            end
        end
    end

    local marker = Collection.trainingMarker(code)
    if marker then
        table.insert(spots, { pos = marker, model = nil })
    end

    return spots
end

function Collection.skipTraining()
    return pcall(function()
        Event:FireServer("training_signaler", "Stop", true)
    end)
end

function Collection.taskProgress(code)
    local folder = Collection.questsFolder()
    local holder = folder and folder:FindFirstChild("Holder")
    for _, quest in (holder and holder:GetChildren() or {}) do
        local tasks = quest:FindFirstChild("Tasks")
        for _, questTask in (tasks and tasks:GetChildren() or {}) do
            local codeValue = questTask:FindFirstChild("Code")
            if codeValue ~= nil and codeValue.Value == code then
                local currentValue, maxValue = questTask:FindFirstChild("Value"), questTask:FindFirstChild("Max")
                return (currentValue and currentValue.Value or 0), (maxValue and maxValue.Value or 0), questTask.Name
            end
        end
    end
end

function Collection.runTrainingTask(code)
    local before, maxProgress, label = Collection.taskProgress(code)
    if before == nil then
        return false, "not a task on the held quest"
    end
    if maxProgress > 0 and before >= maxProgress then
        return true, (label or code) .. " already done"
    end

    local spots = Collection.trainingSpots(code)
    if #spots == 0 then
        return false, "no mats or marker for " .. code
    end

    for _, spot in spots do
        local nowValue = Collection.taskProgress(code)
        if nowValue ~= nil and nowValue > before then
            return true, ("%s %d/%d"):format(label or code, nowValue, maxProgress)
        end

        Collection.teleportTo(spot.pos)
        task.wait(0.6)

        local prompt
        local deadline = os.clock() + 5
        repeat
            if spot.model then
                prompt = spot.model:FindFirstChildWhichIsA("ProximityPrompt", true)
            end

            if prompt == nil then
                local rootPart = Collection.myRoot()
                local best
                for _, descendant in workspaceService:GetDescendants() do
                    if descendant:IsA("ProximityPrompt") and descendant.Enabled and descendant.ObjectText == code then
                        local holder = descendant.Parent
                        local good, promptPosition = pcall(function()
                            return holder.Position or holder:GetPivot().Position
                        end)
                        if good and rootPart ~= nil then
                            local gap = (promptPosition - rootPart.Position).Magnitude
                            if gap < 40 and (best == nil or gap < best) then
                                best, prompt = gap, descendant
                            end
                        end
                    end
                end
            end

            if prompt == nil then
                task.wait(0.3)
            end
        until prompt ~= nil or os.clock() > deadline

        if prompt ~= nil and prompt.Enabled then
            local holder = prompt.Parent
            local good, promptPosition = pcall(function()
                return holder.Position or holder:GetPivot().Position
            end)
            if good and promptPosition ~= nil then
                Collection.teleportTo(promptPosition)
                task.wait(0.8)
            end

            Collection.fireProx(prompt)
            task.wait(1.5)
            Collection.skipTraining()

            local creditDeadline = os.clock() + 12
            repeat
                task.wait(0.4)
                local after = Collection.taskProgress(code)
                if after ~= nil and after > before then
                    return true, ("%s %d/%d"):format(label or code, after, maxProgress)
                end
            until os.clock() > creditDeadline
        end
    end

    local finalValue = Collection.taskProgress(code)
    if finalValue ~= nil and finalValue > before then
        return true, ("%s %d/%d"):format(label or code, finalValue, maxProgress)
    end

    return false, (label or code) .. " did not credit"
end

function Collection.pendingTrainingCodes()
    local folder = Collection.questsFolder()
    local holder = folder and folder:FindFirstChild("Holder")
    local codes = {}

    for _, quest in (holder and holder:GetChildren() or {}) do
        local tasks = quest:FindFirstChild("Tasks")
        for _, questTask in (tasks and tasks:GetChildren() or {}) do
            local codeValue = questTask:FindFirstChild("Code")
            local currentValue, maxValue = questTask:FindFirstChild("Value"), questTask:FindFirstChild("Max")
            local done = currentValue ~= nil and maxValue ~= nil and maxValue.Value > 0 and currentValue.Value >= maxValue.Value
            if codeValue ~= nil and not done
                and (Collection.TRAINING_FOLDER[codeValue.Value] or Collection.trainingMarker(codeValue.Value)) then
                table.insert(codes, codeValue.Value)
            end
        end
    end

    return codes
end

function Collection.lootOnce()
    local rootPart = Collection.myRoot()
    local fired = 0

    local function tryPrompt(prompt)
        if prompt == nil or not prompt.Enabled then
            return
        end

        local range = config.LootRange or 0
        if range > 0 and rootPart ~= nil then
            local part = prompt.Parent
            if part ~= nil and part:IsA("BasePart")
                and (part.Position - rootPart.Position).Magnitude > range then
                return
            end
        end

        if Collection.fireProx(prompt) then
            fired = fired + 1
        end
    end

    local drops = workspaceService:FindFirstChild("LootDrops")
    for _, drop in (drops and drops:GetChildren() or {}) do
        tryPrompt(drop:FindFirstChildWhichIsA("ProximityPrompt", true))
    end

    if config.LootChests then
        local chests = workspaceService:FindFirstChild("Chests")
        for _, chest in (chests and chests:GetChildren() or {}) do
            tryPrompt(chest:FindFirstChildWhichIsA("ProximityPrompt", true))
        end
    end

    return fired
end

function Collection.findDialoguePrompt(npcName)
    if npcName == nil then return nil end

    local debree = workspaceService:FindFirstChild("Debree")
    local regions = debree and debree:FindFirstChild("Regions")

    for _, region in (regions and regions:GetChildren() or {}) do
        local stationaryNpcs = region:FindFirstChild("StationaryNpcs")
        local npc = stationaryNpcs and stationaryNpcs:FindFirstChild(npcName)
        if npc then
            for _, descendant in npc:GetDescendants() do
                if descendant:IsA("ProximityPrompt") and descendant.Enabled then
                    return descendant
                end
            end
        end
    end
end

function Collection.allowPrompts()
    local camRoot = replicatedStorage:FindFirstChild("CAM")
    local layout = camRoot and camRoot.Client and camRoot.Client:FindFirstChild("Components")
    layout = layout and layout:FindFirstChild("Layout")
    local visibility = layout and layout:FindFirstChild("Visibility")
    local prompts = visibility and visibility:FindFirstChild("Prompts")
    if prompts ~= nil and prompts.Value == false then
        pcall(function() prompts.Value = true end)
    end
end

function Collection.talkTo(npcName)
    local prompt = Collection.findDialoguePrompt(npcName)
    if prompt == nil then
        return false, "no dialogue prompt on " .. tostring(npcName)
    end

    local part = prompt.Parent
    if part and part:IsA("BasePart") then
        Collection.teleportTo(part.Position)
        task.wait(0.3)
    end

    Collection.allowPrompts()

    local ok = Collection.fireProx(prompt)
    return ok and true or false, ok and "talked" or "fire failed"
end

Collection.EQUIP_SLOTS = { "One", "Two", "Three", "Four", "Five" }

Collection.EQUIP_MODES = {
    balanced = {
        ["Additional Damage Factor"] = 1000, ["Additional Damage"] = 10,
        ["Damage Reduction Factor"] = 800,   ["Damage Reduction"] = 8,
        ["Max Health Factor"] = 600,         ["Max Health"] = 1,
        ["Max Stamina"] = 0.8,               ["Movement Speed Factor"] = 600,
        ["Health Regen Speed"] = 4,          ["Stamina Regen Speed"] = 3,
        ["Block Points"] = 4,                ["Block Regen"] = 4,
    },
    damage  = { ["Additional Damage Factor"] = 1000, ["Additional Damage"] = 10 },
    tank    = { ["Max Health"] = 1, ["Max Health Factor"] = 600,
                ["Damage Reduction Factor"] = 800, ["Damage Reduction"] = 8,
                ["Health Regen Speed"] = 4, ["Block Points"] = 4, ["Block Regen"] = 4 },
    stamina = { ["Max Stamina"] = 1, ["Stamina Regen Speed"] = 4 },
    speed   = { ["Movement Speed Factor"] = 1000 },
}

function Collection.inventoryItems()
    local data = Collection.playerData()
    local outer = data and data:FindFirstChild("Inventory")
    local inner = outer and outer:FindFirstChild("Inventory")
    local items = {}
    for _, item in (inner and inner:GetChildren() or {}) do
        local id = item:FindFirstChild("Id")
        items[#items + 1] = { name = item.Name, id = id and id.Value or nil }
    end
    return items
end

function Collection.equippedSlots(category)
    local data = Collection.playerData()
    local inventory = data and data:FindFirstChild("Inventory")
    local accessories = inventory and inventory:FindFirstChild("Accessories")
    local folder = accessories and accessories:FindFirstChild(category or "Stats")
    local slotValues = {}
    for _, slot in (folder and folder:GetChildren() or {}) do
        slotValues[slot.Name] = slot.Value
    end
    return slotValues
end

function Collection.findItemId(name)
    for _, item in Collection.inventoryItems() do
        if item.name == name then return item.id end
    end
end

Collection.SLOT_ORDER = { "One", "Two", "Three", "Four", "Five" }

function Collection.itemIsCombat(id)
    local data = Collection.playerData()
    local inventory = data and data:FindFirstChild("Inventory")
    local inner = inventory and inventory:FindFirstChild("Inventory")
    for _, item in (inner and inner:GetChildren() or {}) do
        local itemId = item:FindFirstChild("Id") or item:FindFirstChild("id")
        if itemId ~= nil and itemId.Value == id then
            local itemDef = Items and Items[item.Name]
            return itemDef ~= nil and itemDef.HasCombat == true
        end
    end
    return false
end

function Collection.toolbarSlots()
    local data = Collection.playerData()
    local inventory = data and data:FindFirstChild("Inventory")
    local toolbar = inventory and inventory:FindFirstChild("Toolbar")
    local slotValues = {}
    for _, slot in (toolbar and toolbar:GetChildren() or {}) do
        slotValues[slot.Name] = slot.Value
    end
    return slotValues
end

function Collection.toolbarEquip(itemName, slot)
    slot = slot or "One"
    local id = Collection.findItemId(itemName)
    if id == nil then return false, "not owned: " .. tostring(itemName) end

    local before = Collection.toolbarSlots()[slot]
    if before == id then return true, "already equipped" end

    pcall(function() Event:FireServer("Toolbar_Equip", slot, id) end)

    local deadline = os.clock() + 2
    repeat task.wait(0.1)
    until Collection.toolbarSlots()[slot] ~= before or os.clock() > deadline

    if Collection.toolbarSlots()[slot] ~= before then return true, "equipped" end
    return false, "NotApplied"
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

function Collection.pressSlotKey(slotName)
    local number = Collection.SLOT_NUMBER[slotName] or tonumber(slotName)
    if number == nil then
        return false, "bad slot " .. tostring(slotName)
    end

    local equipped = Collection.equippedSlotValue()
    if equipped ~= nil then
        if equipped.Value ~= number then
            local ok = pcall(function() equipped.Value = number end)
            return ok, ok and "equipped" or "could not set Items_Config.Equipped"
        end
        return true, "already equipped"
    end

    local ok = pcall(function()
        Event:FireServer("Item_Equip", number)
    end)
    return ok, ok and "equipped (direct)" or "FireServer failed"
end

function Collection.weaponScore(name, mode)
    local itemDef = Items and Items[name]
    local stats = itemDef and itemDef.ActiveToolStats
    if type(stats) ~= "table" then
        return nil
    end

    local weights = Collection.EQUIP_MODES[mode or "balanced"] or Collection.EQUIP_MODES.balanced
    local score = 0
    for statName, statValue in pairs(stats) do
        if type(statValue) == "number" then
            score = score + statValue * (weights[statName] or 0)
        end
    end
    return score
end

function Collection.canEquip(itemName)
    local itemDef = Items and Items[itemName]
    local requirements = itemDef and itemDef.EquipRequirements
    if type(requirements) ~= "table" then
        return true
    end

    local data = Collection.playerData()
    for field, allowed in pairs(requirements) do
        local holder = data and data:FindFirstChild(field)
        local mine = holder and holder:IsA("ValueBase") and holder.Value or nil

        if type(allowed) == "table" then
            local ok = false
            for _, want in pairs(allowed) do
                if mine == want then
                    ok = true
                    break
                end
            end
            if not ok then
                return false, ("%s needs %s %s"):format(itemName, field, tostring(mine))
            end
        elseif mine ~= allowed then
            return false, ("%s needs %s=%s"):format(itemName, field, tostring(allowed))
        end
    end

    return true
end

function Collection.bestWeapon(mode)
    local bestName, bestScore
    for _, item in Collection.inventoryItems() do
        local itemDef = Items and Items[item.name]
        if itemDef ~= nil and itemDef.HasCombat and Collection.canEquip(item.name) then
            local score = Collection.weaponScore(item.name, mode) or 0
            if bestScore == nil or score > bestScore then
                bestName, bestScore = item.name, score
            end
        end
    end
    return bestName, bestScore
end

function Collection.ensureWeapon()
    local want = config.Weapon
    if want == nil then
        want = Collection.bestWeapon(config.EquipMode)
        if want == nil then return false, "no HasCombat item owned" end
    end

    local filled = Collection.toolbarSlots()
    local wantedId = Collection.findItemId(want)

    if wantedId ~= nil then
        for _, name in Collection.SLOT_ORDER do
            if (filled[name] or 0) == wantedId then
                if not Collection.weaponDrawn() then
                    Collection.pressSlotKey(name)
                    task.wait(0.3)
                end
                if Collection.weaponDrawn() then
                    return true, ("%s drawn from %s"):format(want, name)
                end
            end
        end
    end

    local order = { config.WeaponSlot or "One" }
    for _, name in Collection.SLOT_ORDER do
        if name ~= order[1] then
            table.insert(order, name)
        end
    end

    local lastWhy = "no slot accepted the weapon"
    for _, name in order do
        local ok, why = Collection.toolbarEquip(want, name)
        if ok then
            if not Collection.weaponDrawn() then
                Collection.pressSlotKey(name)
                task.wait(0.3)
            end
            return true, Collection.weaponDrawn()
                and ("%s equipped to %s and drawn"):format(want, name)
                or ("%s in %s, not drawn"):format(want, name)
        end
        lastWhy = why or lastWhy
    end

    for _, name in Collection.SLOT_ORDER do
        local id = filled[name] or 0
        if id ~= 0 and Collection.itemIsCombat(id) then
            if not Collection.weaponDrawn() then
                Collection.pressSlotKey(name)
                task.wait(0.3)
            end
            if Collection.weaponDrawn() then
                return true, ("fell back to %s (%s)"):format(name, lastWhy)
            end
        end
    end

    return false, lastWhy
end

function Collection.equipBest()
    if Items == nil then return "no Items module" end

    local weights = Collection.EQUIP_MODES[config.EquipMode] or Collection.EQUIP_MODES.balanced
    local ranked = {}
    for _, item in Collection.inventoryItems() do
        local itemDef = Items[item.name]
        local stats = itemDef and itemDef.Stats
        if type(stats) == "table" then
            local score = 0
            for statName, statValue in pairs(stats) do
                if type(statValue) == "number" then score = score + statValue * (weights[statName] or 0) end
            end
            ranked[#ranked + 1] = { name = item.name, id = item.id, score = score }
        end
    end
    if #ranked == 0 then return "no stat-bearing items owned" end

    table.sort(ranked, function(a, b) return a.score > b.score end)

    local worn, taken = Collection.equippedSlots("Stats"), {}
    for _, wornId in pairs(worn) do
        if wornId ~= 0 then taken[wornId] = true end
    end

    local rankIndex, sent, stuck = 1, 0, 0
    for _, slot in Collection.EQUIP_SLOTS do
        while rankIndex <= #ranked and taken[ranked[rankIndex].id] do rankIndex = rankIndex + 1 end
        if rankIndex > #ranked then break end
        local pick = ranked[rankIndex]
        if worn[slot] ~= pick.id then
            pcall(function()
                Event:FireServer("AccessoryEquip", slot, pick.id, "Stats")
            end)
            taken[pick.id] = true
            sent = sent + 1
            task.wait(0.4)

            local after = Collection.equippedSlots("Stats")
            if after[slot] == pick.id then
                stuck = stuck + 1
            end
        end
        rankIndex = rankIndex + 1
    end

    if sent > 0 and stuck == 0 then
        return ("%d sent, NONE applied - the server refused every AccessoryEquip"):format(sent)
    end
    return ("%d equipped (%d sent)"):format(stuck, sent)
end

function Collection.clanTier(name)
    if ClansModule == nil or type(ClansModule.TierOf) ~= "function" then return 0, "?" end
    local ok, tier = pcall(ClansModule.TierOf, name)
    if ok and type(tier) == "table" then return tonumber(tier.rarity) or 0, tostring(tier.name) end
    return 0, "?"
end

function Collection.spinsLeft()
    local data = Collection.playerData()
    local spinning = data and data:FindFirstChild("Spinning")
    local paid = spinning and spinning:FindFirstChild("Spins")
    local free = spinning and spinning:FindFirstChild("FreeClanSpins")
    return (paid and paid.Value or 0) + (free and free.Value or 0)
end

function Collection.spinUntilRarity(minRarity)
    local done = 0
    while Collection.alive() and Collection.spinsLeft() >= 1 do
        local before = Collection.spinsLeft()
        local ok, result = pcall(function()
            return SpinFunction:InvokeServer("ClanSpin")
        end)
        if not ok then return done, "invoke failed" end
        pcall(function() Event:FireServer("ClanSpinComplete") end)
        done = done + 1

        local rarity, label = Collection.clanTier(tostring(result))
        Collection.log(("spin %d -> %s [%s]"):format(done, tostring(result), label))
        if rarity >= minRarity then return done, "found " .. tostring(result) end
        if Collection.spinsLeft() >= before then return done, "count did not drop" end
        task.wait(0.35)
    end
    return done, "out of spins"
end

function Collection.runDiagnostic()
    local pass, fail = 0, 0

    local function ok(name, detail)
        pass = pass + 1
        print(("[ok]   %-30s %s"):format(name, detail or ""))
    end

    local function bad(name, detail)
        fail = fail + 1
        warn(("[FAIL] %-30s %s"):format(name, detail or ""))
    end

    local function check(name, probe)
        local good, passed, detail = pcall(probe)
        if not good then
            bad(name, "errored: " .. tostring(passed))
        elseif passed then
            ok(name, detail)
        else
            bad(name, detail)
        end
    end

    print("=========== diagnostic ===========")

    local data = Collection.playerData()

    check("player data", function()
        return data ~= nil, data and data:GetFullName() or "GetData returned nil"
    end)

    check("combat route", function()
        return true, Collection.route == 1 and "1 punch(getsenv)" or Collection.route == 2 and "2 Do(require)" or "3 raw remote"
    end)

    check("ComboValue", function()
        return Collection.ComboValue ~= nil, Collection.ComboValue and ("= " .. tostring(Collection.ComboValue.Value)) or "missing"
    end)

    check("preset", function()
        local name = Collection.presetFromTools()
        local preset = name and Combat_presets and Combat_presets.Presets[name]
        if preset == nil then
            return false, "unresolved - nothing equipped?"
        end
        return true, ("%s default=%s final=%s"):format(name, tostring(preset.default), tostring(preset.final))
    end)

    check("Checker.check(combat)", function()
        if Checker == nil then return false, "no Checker" end
        local good, result = pcall(Checker.check, localPlayer, "combat")
        return good, good and ("returns " .. tostring(result)) or tostring(result)
    end)

    check("weapon drawn", function()
        local slot = Collection.equippedSlotValue()
        if slot == nil then return false, "Items_Config.Equipped missing" end
        return true, ("slot %d%s"):format(slot.Value, slot.Value == 0 and " - NOTHING DRAWN" or "")
    end)

    check("toolbar", function()
        local byId = {}
        for _, item in Collection.inventoryItems() do
            if item.id then byId[item.id] = item.name end
        end
        local bits = {}
        for slot, id in pairs(Collection.toolbarSlots()) do
            if id ~= 0 then bits[#bits + 1] = slot .. "=" .. (byId[id] or ("id" .. id)) end
        end
        return #bits > 0, #bits > 0 and table.concat(bits, " ") or "empty - nothing to draw"
    end)

    check("quests", function()
        local questCount = 0
        for _ in pairs((QuestsModule and QuestsModule.Holder) or {}) do questCount = questCount + 1 end
        return questCount > 0, ("%d known, %d held"):format(questCount, Collection.activeQuestCount())
    end)

    check("AddQuest", function()
        local addQuest = DialogueModule and DialogueModule.Functions and DialogueModule.Functions.AddQuest
        return type(addQuest) == "function", type(addQuest) == "function" and "present" or "missing"
    end)

    check("active tasks", function()
        local holder = data and data:FindFirstChild("Quests")
        holder = holder and holder:FindFirstChild("Holder")
        local bits = {}
        for _, quest in (holder and holder:GetChildren() or {}) do
            local tasks = quest:FindFirstChild("Tasks")
            for _, questTask in (tasks and tasks:GetChildren() or {}) do
                local currentValue, maxValue, codeValue = questTask:FindFirstChild("Value"), questTask:FindFirstChild("Max"), questTask:FindFirstChild("Code")
                bits[#bits + 1] = ("%s %s/%s code=%s"):format(questTask.Name,
                    tostring(currentValue and currentValue.Value), tostring(maxValue and maxValue.Value), tostring(codeValue and codeValue.Value))
            end
        end
        return true, #bits > 0 and table.concat(bits, " | ") or "none held"
    end)

    check("npcs here", function()
        local total, shielded = 0, 0
        for _, active in Collection.npcFolders() do
            for _, folder in active:GetChildren() do
                total = total + 1
                local model = folder:FindFirstChild(folder.Name)
                if model and Collection.isShielded(model) then shielded = shielded + 1 end
            end
        end
        if total == 0 then return false, "no NPCs loaded anywhere" end
        return total > 0, ("%d npcs, %d blocking"):format(total, shielded)
    end)

    check("giver lookup", function()
        local regions = workspaceService:FindFirstChild("Debree")
        regions = regions and regions:FindFirstChild("Regions")
        local npcCount, prompts = 0, 0
        for _, region in (regions and regions:GetChildren() or {}) do
            local stationaryNpcs = region:FindFirstChild("StationaryNpcs")
            for _, npc in (stationaryNpcs and stationaryNpcs:GetChildren() or {}) do
                npcCount = npcCount + 1
                if npc:FindFirstChildWhichIsA("ProximityPrompt", true) then prompts = prompts + 1 end
            end
        end
        return npcCount > 0, ("%d loaded, %d with Dialogue prompt"):format(npcCount, prompts)
    end)

    check("loot", function()
        local folder = workspaceService:FindFirstChild("LootDrops")
        if folder == nil then return false, "LootDrops missing" end
        return true, #folder:GetChildren() .. " drop(s) on the ground"
    end)

    check("spins", function()
        return true, Collection.spinsLeft() .. " left"
    end)

    print(("=========== %d ok, %d failed ==========="):format(pass, fail))
    return pass, fail
end

Collection.netModules = {
    Teleporter = Collection.tryRequire("CAM", "Client", "Modules", "Teleporter"),
    Worlds     = Collection.tryRequire("CAM", "Worlds"),
    SignalFn   = Collection.tryRequire("Communication", "ServerAndClient", "Signals", "SignalFunction"),
}

function Collection.serverRequest(settings, ui)
    if Collection.netModules.Teleporter ~= nil and type(Collection.netModules.Teleporter.Request) == "function" then
        local ok, detail = Collection.netModules.Teleporter.Request(settings, ui)
        return ok == true, tostring(detail or (ok and "teleporting" or "refused"))
    end
    if Collection.netModules.SignalFn ~= nil and type(Collection.netModules.SignalFn.ToServer) == "function" then
        local fired, accepted, message = pcall(Collection.netModules.SignalFn.ToServer, "TeleportServer", settings)
        if not fired then
            return false, "TeleportServer errored: " .. tostring(accepted)
        end
        return accepted == true, tostring(message or "sent")
    end
    return false, "Teleporter module missing"
end


function Collection.joinWorld(which)
    local placeId = tonumber(which)
    if placeId == nil and Collection.netModules.Worlds ~= nil and type(Collection.netModules.Worlds.ByName) == "table" then
        local world = Collection.netModules.Worlds.ByName[which]
        placeId = type(world) == "table" and world.Id or nil
    end
    if placeId == nil and which == "Ouwland" then
        placeId = 136406881576517
    end
    if placeId == nil then
        return false, "unknown world " .. tostring(which)
    end
    if placeId == game.PlaceId then
        return false, "already there"
    end
    return Collection.serverRequest({ placeId = placeId, allowFallback = true },
        { Title = "Travelling", SubTitle = tostring(which) })
end

function Collection.joinPrivateServer(owner, placeId)
    if type(owner) ~= "string" or owner == "" then
        return false, "no owner username"
    end
    return Collection.serverRequest(
        { placeId = placeId or game.PlaceId, privateOwner = owner },
        { Title = "Private Server", SubTitle = owner })
end

Collection.HUD = { status = "starting", gui = nil }

if config.HUD then
    local parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")

    local oldHud = parent:FindFirstChild("amitoofast_hud")
    if oldHud then
        pcall(function() oldHud:Destroy() end)
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "amitoofast_hud"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 9999
    gui.Parent = parent

    local dimFrame = Instance.new("Frame")
    dimFrame.Size = UDim2.fromScale(1, 1)
    dimFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    dimFrame.BackgroundTransparency = 0.12
    dimFrame.BorderSizePixel = 0
    dimFrame.Parent = gui

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
        textLabel.Parent = dimFrame
        return textLabel
    end

    Collection.HUD.name   = label("name",   localPlayer.Name,      26, 0.16, Enum.Font.GothamBold)
    Collection.HUD.state  = label("state",  "Status: starting...", 20, 0.22, Enum.Font.Gotham)
    Collection.HUD.brand = Instance.new("TextButton")
    Collection.HUD.brand.Name = "brand"
    Collection.HUD.brand.AutoButtonColor = false
    Collection.HUD.brand.BackgroundTransparency = 1
    Collection.HUD.brand.Size = UDim2.new(1, -40, 0, 54)
    Collection.HUD.brand.Position = UDim2.new(0, 20, 0.46, 0)
    Collection.HUD.brand.Font = Enum.Font.GothamBlack
    Collection.HUD.brand.TextSize = 46
    Collection.HUD.brand.TextColor3 = Color3.fromRGB(120, 200, 255)
    Collection.HUD.brand.TextStrokeTransparency = 0.6
    Collection.HUD.brand.Text = "amitoofast"
    Collection.HUD.brand.Parent = dimFrame
    Collection.HUD.money  = label("money",  "",                    24, 0.78, Enum.Font.GothamBold,
        Color3.fromRGB(255, 215, 120))
    Collection.HUD.info   = label("info",   "",                    20, 0.84, Enum.Font.Gotham,
        Color3.fromRGB(180, 230, 180))
    Collection.HUD.timers = label("timers", "",                    20, 0.90, Enum.Font.Gotham,
        Color3.fromRGB(215, 215, 215))

    Collection.HUD.gui = gui

    local shown = true
    local function setShown(visible)
        shown = visible and true or false
        dimFrame.BackgroundTransparency = shown and 0.12 or 1
        for _, part in { Collection.HUD.name, Collection.HUD.state, Collection.HUD.money, Collection.HUD.info, Collection.HUD.timers } do
            if part ~= nil then
                part.Visible = shown
            end
        end
        Collection.HUD.brand.TextTransparency = shown and 0 or 0.55
        Collection.HUD.brand.TextStrokeTransparency = shown and 0.6 or 0.9
        return shown
    end

    Collection.track(Collection.HUD.brand.MouseButton1Click:Connect(function()
        setShown(not shown)
    end))

    do
        local userInputService = game:GetService("UserInputService")
        local keyName = tostring(config.HUDKey or "RightShift")
        local ok, keyCode = pcall(function() return Enum.KeyCode[keyName] end)
        if ok and keyCode then
            Collection.track(userInputService.InputBegan:Connect(function(input, typing)
                if typing then return end
                if input.KeyCode == keyCode then
                    setShown(not shown)
                end
            end))
            Collection.log(("hud: click amitoofast or press %s to hide"):format(keyName))
        else
            Collection.log("hud: unknown HUDKey " .. keyName .. " - click the brand instead")
        end
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

    local warned = {}
    local function try(what, callback)
        local ok, err = pcall(callback)
        if not ok and not warned[what] then
            warned[what] = true
            Collection.log(("hud: %s failed - %s"):format(what, tostring(err)))
        end
    end

    task.spawn(function()
        while Collection.alive() do
            Collection.raiseIdentity()

            try("status", function()
                Collection.HUD.state.Text = "Status: " .. tostring(Collection.HUD.status)
            end)

            try("money", function()
                local data     = Collection.playerData()
                local wenValue = data and data:FindFirstChild("Wen")
                Collection.HUD.money.Text = ("%s  %s   |   Lv %d"):format(
                    utf8.char(128176), short(wenValue and wenValue.Value or 0), Collection.playerLevel())
            end)

            try("timers", function()
                local data = Collection.playerData()
                local quests = data and data:FindFirstChild("Quests")
                local holder = quests and quests:FindFirstChild("Holder")

                local questName, progress = "none", ""
                for _, quest in (holder and holder:GetChildren() or {}) do
                    questName = quest.Name
                    local tasks = quest:FindFirstChild("Tasks")
                    for _, questTask in (tasks and tasks:GetChildren() or {}) do
                        local currentValue = questTask:FindFirstChild("Value")
                        local maxValue = questTask:FindFirstChild("Max")
                        if currentValue ~= nil and maxValue ~= nil then
                            progress = (" %d/%d"):format(currentValue.Value, maxValue.Value)
                        end
                    end
                end

                Collection.HUD.questText = ("Quest: %s%s"):format(questName, progress)
            end)

            try("info", function()
                local data = Collection.playerData()
                local powers = data and data:FindFirstChild("Powers")
                local breath = powers and powers:FindFirstChild("Breathing")
                local clan = data and data:FindFirstChild("Clan")

                local style = breath and breath.Value or ""
                if style == "" then style = "none" end
                local clanName = clan and clan.Value or ""
                if clanName == "" then clanName = "none" end

                Collection.raiseIdentity()
                Collection.HUD.info.Text = ("Breathing: %s   |   Clan: %s"):format(style, clanName)
            end)

            try("target", function()
                Collection.raiseIdentity()
                Collection.HUD.timers.Text = ("%s   |   Target: %s"):format(
                    tostring(Collection.HUD.questText or "Quest: none"), tostring(Collection.targetName))
            end)

            task.wait(0.5)
        end
        pcall(function() gui:Destroy() end)
    end)

    Collection.log("hud: on screen")
end

Collection.skillTree = {
    Focus = {
        Health   = { "Health Regen Speed", "Max Health", "Max Stamina" },
        Damage   = { "Health Regen Speed", "Additional Damage", "Max Health" },
        Stamina  = { "Health Regen Speed", "Max Stamina", "Stamina Regen Speed" },
        Tank     = { "Health Regen Speed", "Block Regen", "Block Points", "Max Health" },
        Balanced = { "Health Regen Speed", "Max Stamina", "Max Health",
                     "Additional Damage", "Stamina Regen Speed" },
    },
    order = { "Balanced", "Health", "Damage", "Stamina", "Tank" },
}

function Collection.skillTree.remote()
    local communication   = replicatedStorage:FindFirstChild("Communication")
    local serverAndClient = communication and communication:FindFirstChild("ServerAndClient")
    local signals         = serverAndClient and serverAndClient:FindFirstChild("Signals")
    local signalFunction  = signals and signals:FindFirstChild("SignalFunction")
    return signalFunction and signalFunction:FindFirstChild("Function")
end

function Collection.skillTree.slot()
    return Collection.playerData()
end

function Collection.skillTree.points()
    local slot = Collection.skillTree.slot()
    local skillPoints = slot and slot:FindFirstChild("SkillPoints")
    return skillPoints and skillPoints.Value or 0
end

function Collection.skillTree.rank(name)
    local slot = Collection.skillTree.slot()
    local list = slot and slot:FindFirstChild("SkillTreeUnlockedList")
    local entry = list and list:FindFirstChild(name)
    return entry and entry.Value or 0
end

function Collection.skillTree.config()
    local ok, camRoot = pcall(function() return replicatedStorage.CAM end)
    if not ok then return nil end
    local okConfig, treeConfig = pcall(function()
        return require(camRoot.Global.SkillService.SkillTreeholder.SkillTreeConfig)
    end)
    return okConfig and type(treeConfig) == "table" and treeConfig or nil
end

function Collection.skillTree.tiers(name)
    local ok, camRoot = pcall(function() return replicatedStorage.CAM end)
    if not ok then return 0 end
    local okHolder, holder = pcall(function()
        return require(camRoot.Global.SkillService.SkillTreeholder)
    end)
    if not okHolder or type(holder) ~= "table" or type(holder.GetBranches) ~= "function" then
        return 0
    end

    local good, branches = pcall(holder.GetBranches)
    if not good or type(branches) ~= "table" then return 0 end

    for _, branch in branches do
        local branchIndex = 1
        while branch[branchIndex] ~= nil do
            local subBranch = branch[branchIndex]
            if subBranch.Name == "Stats" then
                local nodeIndex = 1
                while subBranch[nodeIndex] ~= nil do
                    if subBranch[nodeIndex].Name == name then
                        local tierCount = 0
                        while subBranch[nodeIndex][tierCount + 1] ~= nil do tierCount = tierCount + 1 end
                        return tierCount
                    end
                    nodeIndex = nodeIndex + 1
                end
            end
            branchIndex = branchIndex + 1
        end
    end
    return 0
end

function Collection.skillTree.cost(name, nextTier)
    local treeConfig = Collection.skillTree.config()
    local rule = treeConfig and treeConfig[name] and treeConfig[name].Rule
    if rule == nil or rule.Start == nil then
        return 3
    end
    return rule.Start + (nextTier - 1) * (rule.IncrementAmount or 0)
end

function Collection.skillTree.buy(name)
    local remote = Collection.skillTree.remote()
    if remote == nil then
        return false, "SignalFunction missing"
    end
    local ok, result = pcall(function()
        return remote:InvokeServer("UnlockSkillTreeNode", name)
    end)
    if not ok then
        return false, "remote threw"
    end
    return result == true
end

function Collection.skillTree.spend(focusName, budget)
    local list = Collection.skillTree.Focus[focusName] or Collection.skillTree.Focus.Balanced
    local bought, spent = 0, 0
    local before = Collection.skillTree.points()
    budget = budget or before

    local progressed = true
    while progressed do
        progressed = false
        for _, name in list do
            local have    = Collection.skillTree.rank(name)
            local maxTier = Collection.skillTree.tiers(name)
            if maxTier > 0 and have >= maxTier then
            else
                local price = Collection.skillTree.cost(name, have + 1)
                local left  = Collection.skillTree.points()
                if price <= left and spent + price <= budget then
                    if Collection.skillTree.buy(name) then
                        bought = bought + 1
                        spent  = spent + price
                        progressed = true
                        task.wait(0.35)
                    end
                end
            end
        end
    end

    return bought, spent, ("%s: %d node%s, %d sp (%d left)"):format(
        focusName, bought, bought == 1 and "" or "s", spent, Collection.skillTree.points())
end

function Collection.skillTree.trySkills()
    local ok, camRoot = pcall(function() return replicatedStorage.CAM end)
    if not ok then return 0, "no CAM" end
    local okHolder, holder = pcall(function()
        return require(camRoot.Global.SkillService.SkillTreeholder)
    end)
    if not okHolder or type(holder) ~= "table" then return 0, "no holder" end

    local good, branches = pcall(holder.GetBranches)
    if not good or type(branches) ~= "table" then return 0, "no branches" end

    local got = 0
    for _, branch in branches do
        if branch.Name ~= "Character" then
            local branchIndex = 1
            while branch[branchIndex] ~= nil do
                if Collection.skillTree.points() >= 3 and Collection.skillTree.buy(branch[branchIndex].Name) then
                    got = got + 1
                    task.wait(0.35)
                end
                branchIndex = branchIndex + 1
            end
        end
    end
    return got, got > 0 and ("unlocked " .. got) or "none available (mastery gated)"
end

task.spawn(function()
    while Collection.alive() do
        if config.SkillTree and Collection.skillTree.points() > 0 then
            local bought, _, detail = Collection.skillTree.spend(
                tostring(config.SkillFocus or "Balanced"), config.SkillBudget)
            if bought > 0 then
                Collection.log("skilltree:", detail)
            end

            local got, why = Collection.skillTree.trySkills()
            if got > 0 then
                Collection.log("skilltree: " .. why)
            end
        end
        task.wait(30)
    end
end)


Collection.Dungeon = {
    QUEST  = "Ill find the forge(Lv 65)",
    PORTAL = Vector3.new(-1594, 1003, 1145),
    PAD    = "OuwigaharaPromptPad",
    status = "idle",
    entering = false,
}

function Collection.Dungeon.enabled()
    return config.Dungeon == true
        and Collection.playerLevel() >= (tonumber(config.DungeonLevel) or 65)
end

function Collection.Dungeon.hearts()
    local value = localPlayer:GetAttribute("Hearts")
    if value == nil then return nil end
    return tonumber(value) or 0
end

function Collection.Dungeon.spent()
    local hearts = Collection.Dungeon.hearts()
    return hearts ~= nil and hearts <= 0
end

function Collection.Dungeon.questDone()
    local slot = Collection.playerData()
    local quests = slot and slot:FindFirstChild("Quests")
    for _, folder in { "Completed", "Holder" } do
        local subFolder = quests and quests:FindFirstChild(folder)
        for _, entry in (subFolder and subFolder:GetChildren() or {}) do
            if entry.Name == Collection.Dungeon.QUEST then
                return true
            end
        end
    end
    return false
end

function Collection.Dungeon.portalPrompt()
    local map = workspaceService:FindFirstChild("Map")
    local pad = map and map:FindFirstChild(Collection.Dungeon.PAD)
    local prompt = pad and pad:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt ~= nil then return prompt end

    for _, descendant in workspaceService:GetDescendants() do
        if descendant:IsA("ProximityPrompt") and descendant.Name == "Ouwigahara"
            and descendant.ActionText == "Enter" then
            return descendant
        end
    end
end

function Collection.Dungeon.enter()
    if Collection.Dungeon.spent() then
        return false, "out of lives - the portal will not take you again"
    end
    if not Collection.Dungeon.questDone() then
        return false, "forge quest not done - talk to Blacksmith Togane"
    end

    Collection.Dungeon.entering = true
    Collection.questTravel = true
    Collection.target, Collection.targetRoot = nil, nil

    if not Collection.teleportTo(Collection.Dungeon.PORTAL) then
        Collection.Dungeon.entering, Collection.questTravel = false, false
        return false, "no character"
    end

    local prompt
    local deadline = os.clock() + 8
    repeat
        prompt = Collection.Dungeon.portalPrompt()
        if prompt == nil then
            Collection.questTravel = true
            Collection.teleportTo(Collection.Dungeon.PORTAL)
            task.wait(0.3)
        end
    until prompt ~= nil or os.clock() > deadline

    if prompt == nil then
        Collection.Dungeon.entering, Collection.questTravel = false, false
        return false, "portal prompt never streamed in"
    end
    if not prompt.Enabled then
        Collection.Dungeon.entering, Collection.questTravel = false, false
        return false, "portal disabled"
    end

    Collection.fireProx(prompt)
    return true, "portal fired"
end

task.spawn(function()
    while Collection.alive() do
        if Collection.Dungeon.enabled() and game.PlaceId == 136406881576517 and not Collection.Dungeon.spent() then
            local ok, detail = Collection.Dungeon.enter()
            Collection.Dungeon.status = tostring(detail)
            Collection.log("dungeon: enter - " .. tostring(detail))
            task.wait(ok and 12 or 8)
            Collection.Dungeon.entering, Collection.questTravel = false, false
        else
            task.wait(5)
        end
    end
end)

_G.KaitunDungeon = Collection.Dungeon

Collection.Boss = {
    LIST = {
        { weapon = "Cutlass",       boss = "Zuko",   level = 10,  drop = 20, respawn = 135,
            spot = Vector3.new(-296.7, 1224.2, -1022.2) },
        { weapon = "Sickles",       boss = "Hoyuzo", level = 50,  drop = 15, respawn = 180,
            spot = Vector3.new(746.9, 1001, -1413) },
        { weapon = "Bladed Wagasa", boss = "Fujiko", level = 50,  drop = 5,  respawn = 180,
            spot = Vector3.new(-2459.5, 37.9, 1119) },
        { weapon = "Blood Sickles", boss = "Gyutai", level = 125, drop = 7,  respawn = 300,
            spot = Vector3.new(-266.1, 1043.2, -1139.7) },
        { weapon = "War Fans",      boss = "Domae",  level = 125, drop = 7,  respawn = 300,
            spot = Vector3.new(-296.5, 1350.5, -3451.3) },
        { weapon = "Flame Katana",  boss = "Rengu",  level = 125, drop = 5,  respawn = 300,
            spot = Vector3.new(-712.9, 965, 883.8) },
        { weapon = "Wind Katana",    boss = "Saneri",  level = 125, respawn = 300,
            spot = Vector3.new(-379.1, 1093.5, -422.4) },
        { weapon = "Water Katana",   boss = "Giyen",   level = 125, respawn = 300,
            spot = Vector3.new(388.9, 1018, -85.1) },
        { weapon = "Thunder Katana", boss = "Zentaro", level = 125, respawn = 300,
            spot = Vector3.new(1332.1, 821.5, -1017.6) },
        { weapon = "Sound Katanas",  boss = "Tengai",  level = 125, respawn = 300,
            spot = Vector3.new(-133.5, 1349, -2631.3) },
        { weapon = "Serpent Katana", boss = "Obari",   level = 125, respawn = 300,
            spot = Vector3.new(770.5, 1121, -1047) },
        { weapon = "Claws",          boss = "Kaiden",  level = 50,  respawn = 165,
            spot = Vector3.new(585.7, 1146.5, -1314.9) },
    },
    active = nil,
    status = "off",
}

function Collection.Boss.wanted()
    local raw = config.BossWeapons
    if raw == nil then return nil end
    local wantedSet = {}
    if type(raw) == "string" then
        for name in string.gmatch(raw, "[^,]+") do
            wantedSet[(string.gsub(name, "^%s*(.-)%s*$", "%1"))] = true
        end
    elseif type(raw) == "table" then
        for key, value in pairs(raw) do
            if type(key) == "number" then wantedSet[tostring(value)] = true
            elseif value then wantedSet[tostring(key)] = true end
        end
    end
    return wantedSet
end

function Collection.Boss.owned(weapon)
    local slot = Collection.playerData()
    local inventory = slot and slot:FindFirstChild("Inventory")
    inventory = inventory and inventory:FindFirstChild("Inventory")
    return inventory ~= nil and inventory:FindFirstChild(weapon) ~= nil
end

function Collection.Boss.raceBlock(weapon)
    local itemDef = Items and Items[weapon]
    local requirements = itemDef and itemDef.EquipRequirements
    local races = requirements and requirements.Race
    if type(races) ~= "table" then return nil end
    local slot = Collection.playerData()
    local race = slot and slot:FindFirstChild("Race")
    race = race and tostring(race.Value) or "?"
    for _, allowed in races do
        if allowed == race then return nil end
    end
    return ("%s is %s only (you are %s)"):format(weapon, table.concat(races, "/"), race)
end

function Collection.Boss.blocked(entry)
    if Collection.playerLevel() < entry.level then
        return ("Lv %d needed for %s"):format(entry.level, entry.boss)
    end
    if not config.BossIgnoreRace then
        local why = Collection.Boss.raceBlock(entry.weapon)
        if why then return why end
    end
    if not config.BossKeepFarming and Collection.Boss.owned(entry.weapon) then
        return entry.weapon .. " already owned"
    end
    return nil
end

function Collection.Boss.eligible()
    local wanted = Collection.Boss.wanted()
    local eligibleList = {}
    for _, entry in Collection.Boss.LIST do
        if (wanted == nil or wanted[entry.weapon]) and Collection.Boss.blocked(entry) == nil then
            table.insert(eligibleList, entry)
        end
    end
    return eligibleList
end

function Collection.Boss.alive(name)
    for _, active in Collection.npcFolders() do
        local folder = active:FindFirstChild(name)
        local model = folder and folder:FindFirstChild(name)
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        if humanoid ~= nil and humanoid.Health > 0 then
            return model
        end
    end
    return nil
end

function Collection.Boss.release()
    if Collection.Boss.active ~= nil then
        Collection.Boss.active = nil
        Collection.behindTargets = {}
        Collection.target, Collection.targetRoot = nil, nil
    end
end

task.spawn(function()
    local waitingSince, waitingFor = 0, nil
    while Collection.alive() do
        if not (config.BossFarm and config.Enabled and game.PlaceId == 136406881576517)
            or Collection.Dungeon.entering then
            Collection.Boss.release()
            Collection.Boss.status = config.BossFarm and "paused" or "off"
            task.wait(2)
            continue
        end

        local list = Collection.Boss.eligible()
        if #list == 0 then
            Collection.Boss.release()
            Collection.Boss.status = "nothing eligible"
            task.wait(10)
            continue
        end

        local entry = list[1]
        for _, candidate in list do
            if Collection.Boss.alive(candidate.boss) then entry = candidate break end
        end

        if waitingFor ~= entry then
            waitingFor, waitingSince = entry, os.clock()
            Collection.log(("boss: farming %s for %s (%s%% drop)"):format(entry.boss, entry.weapon, tostring(entry.drop or "?")))
        end

        if Collection.Boss.active ~= entry then
            Collection.target, Collection.targetRoot = nil, nil
        end
        Collection.Boss.active = entry
        Collection.behindTargets = { [entry.boss] = true }

        local model = Collection.Boss.alive(entry.boss)
        if model == nil then
            local rootPart = Collection.myRoot()
            if rootPart ~= nil and (rootPart.Position - entry.spot).Magnitude > 60 then
                Collection.teleportTo(entry.spot)
            end
            Collection.Boss.status = ("waiting for %s (%s)"):format(entry.boss, entry.weapon)
            Collection.HUD.status = "boss: " .. Collection.Boss.status

            if #list > 1 and os.clock() - waitingSince > entry.respawn + 45 then
                table.insert(Collection.Boss.LIST, table.remove(Collection.Boss.LIST, table.find(Collection.Boss.LIST, entry)))
                Collection.log(("boss: %s not up after %ds - rotating"):format(entry.boss, entry.respawn + 45))
                waitingFor = nil
            end
            task.wait(1)
        else
            Collection.Boss.status = ("fighting %s for %s"):format(entry.boss, entry.weapon)
            Collection.HUD.status = "boss: " .. Collection.Boss.status
            waitingSince = os.clock()
            task.wait(1)
            if Collection.Boss.alive(entry.boss) == nil then
                task.wait(4)
                if Collection.Boss.owned(entry.weapon) then
                    Collection.log(("boss: %s obtained"):format(entry.weapon))
                end
            end
        end
    end
    Collection.Boss.release()
end)

_G.KaitunBoss = Collection.Boss

_G.KaitunDiagnostic = Collection.runDiagnostic

_G.KaitunWorld   = Collection.joinWorld
_G.KaitunDrop    = Collection.abandonQuest
_G.KaitunPrivate = Collection.joinPrivateServer

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

task.spawn(function()
    while Collection.alive() do
        if config.Dungeon and game.PlaceId == 75556147183481 then
            task.wait(3)
        elseif config.AutoOuwland and game.PlaceId ~= 136406881576517 then
            local owner = config.PrivateServerOwner
            local ok, detail
            if type(owner) == "string" and owner ~= "" then
                ok, detail = Collection.joinPrivateServer(owner, 136406881576517)
            else
                ok, detail = Collection.joinWorld("Ouwland")
            end

            Collection.log(("ouwland: wrong place (%s)%s - %s"):format(
                tostring(game.PlaceId),
                type(owner) == "string" and owner ~= "" and (" via " .. owner) or "",
                tostring(ok and "travelling" or detail)))
            task.wait(10)
        else
            task.wait(3)
        end
    end
end)

if config.Diagnostic then
    Collection.runDiagnostic()
end

if config.AutoEquipWeapon then
    local ok, why = Collection.ensureWeapon()
    Collection.log("weapon:", config.Weapon or "(first owned)", config.WeaponSlot, ok and why or ("FAILED " .. tostring(why)))
end

if config.EquipBest then
    Collection.log("equip best:", Collection.equipBest())
end

if config.Spin then
    local spins, why = Collection.spinUntilRarity(config.SpinUntilRarity)
    Collection.log(("spun %d times: %s"):format(spins, why))
end

task.spawn(function()
    local SLOT_BY_NUMBER = { "One", "Two", "Three", "Four", "Five" }

    while Collection.alive() do
        if config.AutoEquipWeapon then
            local want = config.Weapon or Collection.bestWeapon(config.EquipMode)
            local wantedId = want and Collection.findItemId(want)
            local filled = Collection.toolbarSlots()

            local equipped = Collection.equippedSlotValue()
            local drawnNum = equipped and equipped.Value or 0
            local drawnSlot = SLOT_BY_NUMBER[drawnNum]
            local drawnId = drawnSlot and (filled[drawnSlot] or 0) or 0

            if wantedId ~= nil and drawnId == wantedId then
            elseif wantedId ~= nil and drawnId ~= wantedId then
                local home
                for _, name in SLOT_BY_NUMBER do
                    if (filled[name] or 0) == wantedId then
                        home = name
                        break
                    end
                end

                if home ~= nil then
                    Collection.pressSlotKey(home)
                    task.wait(0.3)
                    if Collection.weaponDrawn() then
                        Collection.log("drew", want, "from", home)
                    end
                else
                    local ok, why = Collection.ensureWeapon()
                    Collection.log("re-equipped weapon:", ok and why or ("failed " .. tostring(why)))
                end
            elseif not Collection.weaponDrawn() then
                local ok, why = Collection.ensureWeapon()
                Collection.log("re-equipped weapon:", ok and why or ("failed " .. tostring(why)))
            end
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while Collection.alive() do
        task.wait(5)
        local scriptsFolder = localPlayer:FindFirstChild("PlayerScripts")
        local clientFolder = scriptsFolder and scriptsFolder:FindFirstChild("CU")
        local live = clientFolder and clientFolder:FindFirstChild("Combat") or nil
        if live ~= Collection.combatScript or (Collection.route == 3 and live ~= nil) then
            Collection.resolveRoute()
        end
    end
end)

task.spawn(function()
    while Collection.alive() do
        if config.Loot then pcall(Collection.lootOnce) end
        task.wait(0.3)
    end
end)

task.spawn(function()
    while Collection.alive() do
        if not config.Farm then
            task.wait(0.3)
        elseif os.clock() < Collection.comboBackoffUntil then
            task.wait(0.1)
        elseif config.AvoidShield and Collection.targetShielded then
            task.wait(0.2)
        elseif not Collection.weaponDrawn() then
            if config.AutoEquipWeapon then
                Collection.ensureWeapon()
            end
            task.wait(1)
        elseif not Collection.targetValid() then
            task.wait(0.25)
        else
            local nextDelay
            if Collection.route == 1 then
                local ok, nextGap = pcall(Collection.punch)
                nextDelay = ok and nextGap or nil

                if ok then
                    Collection.punchFails = 0
                else
                    Collection.punchFails = Collection.punchFails + 1
                    if Collection.punchFails >= 3 then
                        Collection.route = Collection.Do and 2 or 3
                        Collection.log("punch() route died - falling back to", Collection.routeName())
                    end
                end
            else
                nextDelay = Collection.combatStep()
            end
            task.wait(nextDelay or 0.25)
        end
    end
end)

task.spawn(function()
    local lastTravel, lastStatus = 0, ""
    local dropTried = false

    local function status(text)
        Collection.HUD.status = text
        if text ~= lastStatus then
            lastStatus = text
            Collection.log(text)
        end
    end

    while Collection.alive() do
        if Collection.Dungeon.entering or Collection.Boss.active ~= nil then
            task.wait(0.5)
            continue
        end

        if not config.Quests then
            if not Collection.targetValid() and os.clock() - lastTravel > (config.TravelCooldown or 5) then
                local pos, dist, name = Collection.nearestWanted()
                if pos ~= nil and dist > 12 then
                    Collection.teleportTo(pos)
                    lastTravel = os.clock()
                    status(("travelling %d studs to %s"):format(math.floor(dist), name))
                end
            end
            task.wait(1)
        else
            local active = Collection.activeQuestCount()

            if active > 0 and not dropTried then
                local want = Collection.breathingWanted()
                if want ~= nil then
                    local heldKey, heldName = Collection.activeQuestKey()
                    if heldKey ~= want then
                        dropTried = true
                        local ok, why = Collection.abandonQuest(heldName)
                        status(("%s - taking %s"):format(tostring(why), want))
                        if ok then
                            active = Collection.activeQuestCount()
                        end
                    end
                end
            elseif active == 0 then
                dropTried = false
            end

            if active == 0 then
                local gapItem, gapNeed, gapHave
                if config.AutoBreathing and Collection.playerLevel() >= 25 and not Collection.hasBreathing() then
                    local style = config.BreathingStyle or Collection.BREATHING_STYLES[1]
                    gapItem, gapNeed, gapHave = Collection.breathingItemGap(style)
                end

                if gapItem ~= nil then
                    local spec = Collection.ITEM_FARM[gapItem]

                    local farmKey, farmGiver
                    for _, key in (spec.quests or {}) do
                        if (Collection.farmQuestSkip[key] or 0) <= os.clock() then
                            local fine, giver = Collection.questUsable(key)
                            if fine then
                                farmKey, farmGiver = key, giver
                                break
                            end
                        end
                    end

                    if farmKey ~= nil then
                        local pos = Collection.findGiver(farmGiver)
                        if pos then
                            Collection.teleportTo(pos)
                            task.wait(0.5)
                        end

                        local before = Collection.activeQuestCount()
                        local okAccept, reason = Collection.acceptQuest(farmKey)

                        if okAccept then
                            local deadline = os.clock() + 2
                            repeat task.wait(0.1)
                            until Collection.activeQuestCount() > before or os.clock() > deadline
                        end

                        if Collection.activeQuestCount() > before then
                            Collection.behindTargets = {}
                            lastTravel = 0
                            status(("accepted %s for %s"):format(farmKey, gapItem))
                        else
                            Collection.farmQuestSkip[farmKey] = os.clock() + 120
                            status(("farm quest %s refused: %s")
                                :format(farmKey, tostring(reason or "not granted")))
                        end

                        task.wait(1)
                    else
                        Collection.behindTargets = spec.targets

                        if not Collection.targetValid() and os.clock() - lastTravel > 5 then
                            Collection.teleportTo(spec.position)
                            lastTravel = os.clock()
                        end

                        status(("farming %s %d/%d"):format(gapItem, gapHave, gapNeed))
                        task.wait(1)
                    end
                else
                    local left = Collection.questCooldownLeft()
                    if left > 0 then
                        status(("quest cooldown %ds"):format(math.ceil(left)))
                        task.wait(math.min(left, 5))
                    else
                        local key, pickedGiver, travelFirst = config.Quest, nil, nil
                        if config.AutoPickQuest then
                            local nextKey, nextGiver, nextTravel = Collection.nextEligibleQuest()
                            if nextKey ~= nil then
                                key, pickedGiver, travelFirst = nextKey, nextGiver, nextTravel
                            end
                        end

                        if key == nil then
                            status("nothing eligible right now")
                            task.wait(5)
                        else
                            local giver = Collection.questDef(key)
                            giver = giver and giver.OfferNpc
                            local pos = Collection.findGiver(giver)

                            Collection.questTravel = true
                            Collection.target, Collection.targetRoot = nil, nil

                            if pos == nil and travelFirst ~= nil then
                                status("travelling to reach " .. tostring(giver))
                                Collection.teleportTo(travelFirst)
                                task.wait(4)
                                pos = Collection.findGiver(giver)
                            end

                            if pos then
                                Collection.teleportTo(pos)
                                task.wait(0.5)
                            end

                            local before = Collection.activeQuestCount()
                            local ok, reason = Collection.acceptQuest(key)
                            if not ok then
                                Collection.questTravel = false
                                status("refused " .. key .. ": " .. tostring(reason))
                                task.wait(3)
                            else
                                local deadline = os.clock() + 2
                                repeat task.wait(0.1)
                                until Collection.activeQuestCount() > before or os.clock() > deadline

                                local granted = Collection.activeQuestCount() > before
                                Collection.questTravel = false
                                if granted then
                                    status("accepted " .. key)
                                    Collection.behindTargets = {}
                                    lastTravel = 0
                                else
                                    status("not granted - too far from " .. tostring(giver))
                                    task.wait(4)
                                end
                            end
                        end
                    end
                end
            elseif Collection.allTasksComplete() then
                local key, display = Collection.activeQuestKey()
                local questDefinition = key and Collection.questDef(key)
                local giver = questDefinition and questDefinition.OfferNpc

                if os.clock() - lastTravel > 4 then
                    local ok, why = Collection.talkTo(giver)
                    lastTravel = os.clock()
                    status("turning in " .. tostring(display) .. " at "
                        .. tostring(giver) .. " - " .. tostring(why))
                end

                task.wait(2)
            else
                local pending = Collection.pendingTrainingCodes()
                if #pending > 0 then
                    Collection.questTravel = true
                    Collection.target, Collection.targetRoot = nil, nil
                    status(("training: %d left (%s)"):format(#pending, pending[1]))

                    local fired, done, why = pcall(Collection.runTrainingTask, pending[1])
                    if not fired then
                        Collection.log("training errored:", tostring(done))
                    else
                        Collection.log("training:", done and "ok" or "no", tostring(why))
                    end

                    Collection.questTravel = false
                    task.wait(0.5)
                else
                    Collection.behindTargets = Collection.resolveQuestTargets()

                    if not Collection.targetValid() and os.clock() - lastTravel > config.TravelCooldown then
                        local key = Collection.activeQuestKey()
                        local pos = key and Collection.questWaypoint(key)
                        if pos then
                            Collection.teleportTo(pos)
                            lastTravel = os.clock()
                            status("travelling to objective")
                        end
                    end

                    local typeCount = 0
                    for _ in pairs(Collection.behindTargets) do typeCount = typeCount + 1 end
                    status(("farming (%d target type%s)"):format(typeCount, typeCount == 1 and "" or "s"))
                    task.wait(1)
                end
            end
        end
    end

    Collection.log("stopped")
end)

Collection.log("running - getgenv().Config.Enabled = false to stop")
