-- mantle v0.2
-- by vtastek
-- Adds climbing to Morrowind


local logger = require("logging.logger")
local log = logger.new{
    name = "Mantle of Ascension",
    logLevel = "TRACE",
    logToConsole = true,
    includeTimestamp = true,
}

local jumpKeyCode -- current jump key



-- modules
local config = require("mantle.config")
local skillsModule = include("SkillsModule") ---@type SkillsModule?

local climbSkill ---@type SkillsModule.Skill
if skillsModule then
    climbSkill = skillsModule.registerSkill{
        id = "climbing",
        name = "Climbing",
        description = "Climbing is a skill checked whenever one attempts to scale a wall or a steep incline. \z
            Skilled individuals can climb longer by getting exhausted later.",
        icon = "Icons/vt/climbing.dds",
        specialization = tes3.specialization.stealth,
        value = 10,
    }
end
if not climbSkill then config.trainClimbing = false end
skillsModule = nil



-- state
local isClimbing = false

-- constants
local CLIMB_TIMING_WINDOW = 0.15
local CLIMB_RAYCAST_COUNT = 15
local CLIMB_MIN_DISTANCE = 50/3
local UP = tes3vector3.new(0, 0, 1)
local DOWN = tes3vector3.new(0, 0, -1)
local MIN_ANGLE = math.rad(45)

local MAX_XP_CLIMB_DIST = 10000

--
-- Skill Progress
--



--
-- Fatigue Cost
--

local function getEncumbRatio(mob)
    return mob.encumbrance.current / mob.encumbrance.base
end

local function getJumpFatigueCost()
    local jumpBase = tes3.findGMST(tes3.gmst.fFatigueJumpBase).value
    local jumpMult = tes3.findGMST(tes3.gmst.fFatigueJumpMult).value
    local encRatio = getEncumbRatio(tes3.mobilePlayer)
    return jumpBase + encRatio * jumpMult
end

local function applyClimbingFatigueCost()
    local skillCheckAverage = 0
    local skillCheckDivider = 0

    if config.trainAcrobatics then
        skillCheckAverage = tes3.mobilePlayer.acrobatics.current
        skillCheckDivider = 1
    end

    if config.trainAthletics then
        skillCheckAverage = skillCheckAverage + tes3.mobilePlayer.athletics.current
        skillCheckDivider = skillCheckDivider + 1
    end

    if config.trainClimbing then
        skillCheckAverage = skillCheckAverage + climbSkill.current
        skillCheckDivider = skillCheckDivider + 1
    end

    if skillCheckDivider > 0 then
        skillCheckAverage = skillCheckAverage / skillCheckDivider -- only divide for the active skills
    end

    local climbCost = math.min(
        tes3.mobilePlayer.fatigue.current,
        getJumpFatigueCost() * 2 * math.max(0.1, 1 - skillCheckAverage / 100)
    )
    tes3.modStatistic{reference = tes3.player, name = "fatigue", current = -climbCost}
end

--
-- Sounds
--

-- playSound wrapper that accepts time delay parameter
local function playSound(t)
    if t.delay == nil then
        tes3.playSound(t)
    else
        timer.start{duration = t.delay, callback = function() tes3.playSound(t) end}
    end
end

--
-- Debug Stuff
--

-- create a widget to help visualize ray results
local function debugPlaceWidget(widgetId, position, intersection)
    local root = tes3.game.worldSceneGraphRoot.children[9]
    assert(root.name == "WorldVFXRoot")

    local node = root:getObjectByName(widgetId)
    if not node then
        node = tes3.loadMesh("g7\\widget_raytest.nif"):clone()
        node.name = widgetId
        root:attachChild(node)
    end
    node.translation = intersection
    node:update()

    local base = node:getObjectByName("Base")
    local t = base.parent.worldTransform
    base.translation = (t.rotation * t.scale):invert() * (position - t.translation)
    base:update()

    root:update()
    root:updateProperties()
    root:updateNodeEffects()
end

-- rayTest wrapper that also places a visual aid
local function rayTest(t)
    local rayhit = tes3.rayTest(t)
    if rayhit and config.enableDebugWidgets and t.widgetId then
        debugPlaceWidget(t.widgetId, t.position, rayhit.intersection)
    end
    return rayhit
end

--
-- Climbing
--

local function getCeilingDistance(pos)
    pos = pos or tes3.getPlayerEyePosition()
    local rayhit = tes3.rayTest{position = pos, direction = UP, ignore = {tes3.player}}
    return rayhit and rayhit.distance or math.huge
end

local function getClimbingDestination()
    local position = tes3.player.position

    -- we will raycasts from 200 units above player
    local rayPosition = position + (UP * 200)

    -- build forward vector without any upward tilt
    local forward = tes3.getPlayerEyeVector()
    forward.z = 0
    forward:normalize()

    -- require destination to be above player waist
    local waistHeight = tes3.mobilePlayer.height * 0.5

    -- tracking angle to prevent climbing up stairs
    local destination = nil
    local destinationAngle = MIN_ANGLE
    local maxVecZ = -math.huge -- Initialize with negative infinity

    -- raycast down from increasing forward offsets
    for i=1, 8 do
        local rayhit = rayTest{
            widgetId = "widget_" .. i,
            position = rayPosition + forward * (CLIMB_MIN_DISTANCE * i),
            direction = DOWN,
            ignore = {tes3.player},
        }
        if rayhit then
            local vec = rayhit.intersection - position
            if vec.z >= waistHeight then
                local angle = math.acos(vec:normalized():dot(forward))
                if angle > destinationAngle then
                    destinationAngle = angle
                    destination = rayhit.intersection:copy()
                end
                maxVecZ = math.max(maxVecZ, -vec.z)
            end
        end
    end

    if destination and getCeilingDistance(destination) >= 64 then
        return destination, maxVecZ
    end
end

local function climbPlayer(deltaZ, speed)
    -- avoid sending us through the ceiling
    if getCeilingDistance() < 20 then return end

    local mob = tes3.mobilePlayer
    local pos = mob.reference.position

    -- equalizing instead gets consistent results
    local verticalClimb = deltaZ / 600 * speed
    if verticalClimb > 0 then
        local previous = pos:copy()
        pos.z = pos.z + verticalClimb
        mob.velocity = pos - previous
    end
end


local function doneClimbing(maxVecZ)
    isClimbing = false 
    -- tes3.messageBox(maxVecZ)
    -- local jumpXP = tes3.getSkill(tes3.skill.acrobatics).actions[1]
    
    local maxDrop = -maxVecZ

    if maxDrop <= 0 then return end

    maxDrop = math.min(maxDrop, MAX_XP_CLIMB_DIST)

    local xp = math.lerp(1, 5, maxDrop / MAX_XP_CLIMB_DIST)

    if config.trainClimbing then
        climbSkill:exercise(xp)
    end

    if config.trainAthletics then
        tes3.mobilePlayer:exerciseSkill(tes3.skill.athletics, xp/3)
    end
    if config.trainAcrobatics then
        tes3.mobilePlayer:exerciseSkill(tes3.skill.acrobatics, xp/2)
    end

end

local function startClimbing(deltaZ, maxVecZ)
    local mob = tes3.mobilePlayer

    -- disable the swimming physics systems
    mob.isSwimming = false

    -- player encumbrance/fatigue penalties
    local climbDuration = 0.4
    if (mob.fatigue.current <= 0) or getEncumbRatio(mob) >= 0.85 then
        climbDuration = 2.0
        deltaZ = deltaZ - mob.height * 0.8
        playSound{sound = 'Item Armor Light Down', volume = 1.0, pitch = 1.3, delay = 0.2}
    end

    -- set climbing state until it finished
    isClimbing = true
    
    
    timer.start{duration = climbDuration, callback = function() doneClimbing(maxVecZ) end}

    -- trigger the actual climbing function
    local speed = (mob.moveSpeed < 100) and 1.5 or 2.0
    timer.start{
        duration = 1/600,
        iterations = 600/speed,
        callback = function()
            climbPlayer(deltaZ, speed)
        end,
    }

    -- trigger climbing started sound after 0.1s
    playSound{sound = 'corpDRAG', volume = 0.6, pitch = 0.8, delay = 0.1}

    -- trigger climbing finished sound after 0.7s
    playSound{sound = 'corpDRAG', volume = 0.3, pitch = 1.3, delay = 0.7}
end

local function attemptClimbing()
    local destination, maxVecZ = getClimbingDestination()
    if destination == nil or maxVecZ == nil then
        return
    end

    -- how much to move upwards
    -- bias for player bounding box
    startClimbing(64 + destination.z - tes3.player.position.z, maxVecZ)

    

    

    applyClimbingFatigueCost()

    return true
end

local function onKeyDownJump()
    local mob = tes3.mobilePlayer

    if tes3ui.menuMode() then
        return
    elseif mob.isFlying or isClimbing then
        return
    elseif config.disableThirdPerson and tes3.is3rdPerson() then
        return
    end

    -- prevent climbing while downed/dying/etc
    local attackState = mob.actionData.animationAttackState
    if attackState ~= tes3.animationState.idle then
        return
    end

    -- disable during chargen, -1 is all done
    if tes3.getGlobal('ChargenState') ~= -1 then
        return
    end

    -- falling too fast
    -- acrobatics 25 fastfall 100 -1000
    -- acrobatics 100 fastfall 25 -2000
    local velocity = mob.velocity
    local fastfall = 125 - mob.acrobatics.current
    if fastfall > 0 then
        if velocity.z < -10 * (-1.5 * fastfall + 250) then
            if config.trainClimbing then climbSkill:exercise(5) end
            return
        end
    end

    local climbTimer
    climbTimer = timer.start{
        duration = CLIMB_TIMING_WINDOW / CLIMB_RAYCAST_COUNT,
        iterations = CLIMB_RAYCAST_COUNT,
        callback = function()
            if attemptClimbing() then
                climbTimer:cancel()
            end
        end
    }
    climbTimer.callback()
end





--
-- Events
--




local function updateJumpKey()

    local oldJumpKeyCode = jumpKeyCode

    jumpKeyCode = tes3.getInputBinding(tes3.keybind.jump).code ---@type tes3.scanCode

    if event.isRegistered(tes3.event.menuExit, updateJumpKey) then
        -- log:debug("updateJumpKey was registered to menuExit, unregistering...")
        event.unregister(tes3.event.menuExit, updateJumpKey) 
    end

    if event.isRegistered(tes3.event.keyDown, onKeyDownJump, {filter = oldJumpKeyCode}) then
        event.unregister(tes3.event.keyDown, onKeyDownJump, {filter = oldJumpKeyCode})
    end

    -- log:debug("jump key updated to %s", table.find(tes3.scanCode, jumpKeyCode))

    event.register(tes3.event.keyDown, onKeyDownJump, {filter = jumpKeyCode})
end

local function MenuCtrlsActivated()
    -- log:debug("menu ctrls activated! registering update jump key event")
    event.register(tes3.event.menuExit, updateJumpKey)
end


event.register("initialized",function()
    log:info("Initialized.")
    updateJumpKey()
    event.register("uiActivated", MenuCtrlsActivated, {filter="MenuCtrls"})
    require "mantle.mcm"
end)
