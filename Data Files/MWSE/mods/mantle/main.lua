-- mantle v0.2
-- by vtastek
-- Adds climbing to Morrowind

mwse.log("[Mantle of Ascension] Version 0.0.1")

-- modules
local config = require("mantle.config")
local skillModuleClimb = include("OtherSkills.skillModule")

-- state
local isClimbing = false

-- constants
local CLIMB_TIMING_WINDOW = 0.15
local CLIMB_RAYCAST_COUNT = 15
local CLIMB_MIN_DISTANCE = 50/3
local UP = tes3vector3.new(0, 0, 1)
local DOWN = tes3vector3.new(0, 0, -1)

--
-- Skill Progress
--

local function getJumpExperienceValue()
    return tes3.getSkill(tes3.skill.acrobatics).actions[1]
end

local function applyAcrobaticsProgress()
    if config.trainAcrobatics then
        tes3.mobilePlayer:exerciseSkill(tes3.skill.acrobatics, getJumpExperienceValue())
    end
end

local function applyAthleticsProgress()
    if config.trainAthletics then
        tes3.mobilePlayer:exerciseSkill(tes3.skill.athletics, getJumpExperienceValue())
    end
end

local function applyClimbingProgress(value)
    skillModuleClimb.incrementSkill("climbing", {progress = value})
end

--
-- Fatigue Cost
--

local function getEncumbRatio(mob)
    return mob.encumbrance.current / mob.encumbrance.base
end

local function getJumpFatigueCost()
    local jumpBase = tes3.findGMST('fFatigueJumpBase').value
    local jumpMult = tes3.findGMST('fFatigueJumpMult').value
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

    if skillModuleClimb ~= nil and config.trainClimbing then
        skillCheckAverage = skillCheckAverage + skillModuleClimb.getSkill("climbing").value
        skillCheckDivider = skillCheckDivider + 1
    end

    if skillCheckDivider > 0 then
        skillCheckAverage = skillCheckAverage / skillCheckDivider -- only divide for the active skills
    end

    skillCheckAverage = math.max(0.1, 1 - skillCheckAverage / 100)
    local climbCost = getJumpFatigueCost() * 2 * skillCheckAverage

    tes3.modStatistic{reference = tes3.player, name = "fatigue", current = (-climbCost), limit = true}
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

local function getCeilingDistance()
    local eyePos = tes3.getPlayerEyePosition()
    local rayhit = tes3.rayTest{position = eyePos, direction = UP, ignore = {tes3.player}}
    return rayhit and rayhit.distance or math.huge
end

local function getClimbingDestination()
    local destination = tes3.player.position:copy()

    -- we will raycasts from 200 units above player
    local rayPosition = destination + (UP * 200)

    -- build forward vector without any upward tilt
    local forward = tes3.getPlayerEyeVector()
    forward.z = 0
    forward:normalize()

    -- raycast down from increasing forward offsets
    for i=1, 8 do
        local rayhit = rayTest{
            widgetId = "widget_" .. i,
            position = rayPosition + forward * (CLIMB_MIN_DISTANCE * i),
            direction = DOWN,
            ignore = {tes3.player},
        }
        if rayhit then
            -- only keep the intersection highest z
            if rayhit.intersection.z > destination.z then
                destination = rayhit.intersection:copy()
            end
        end
    end

    -- ignore if destination is below player waist
    local vec = destination - tes3.player.position
    if vec.z < tes3.mobilePlayer.height * 0.5 then
        return
    end

    -- minimum angle to prevent climbing up stairs
    local angle = math.acos(vec:normalized():dot(forward))
    if angle <= math.rad(45) then
        return
    end

    return destination
end

local function climbPlayer(destinationZ, speed)
    -- some bias to prevent clipping through floors
    if getCeilingDistance() < 20 then return end

    local mob = tes3.mobilePlayer
    local pos = mob.reference.position

    -- equalizing instead gets consistent results
    local verticalClimb = destinationZ / 600 * speed
    if verticalClimb > 0 then
        local previous = pos:copy()
        pos.z = pos.z + verticalClimb
        mob.velocity = pos - previous
    end
end

local function startClimbing(destinationZ)
    local mob = tes3.mobilePlayer

    -- player encumbrance/fatigue penalties
    local climbDuration = 0.4
    if (mob.fatigue.current <= 0) or getEncumbRatio(mob) >= 0.85 then
        climbDuration = 2.0
        destinationZ = destinationZ - mob.height * 0.8
        playSound{delay = 0.8, sound = 'Item Armor Light Down', volume = 0.5, pitch = 1.3}
    end

    -- set climbing state until finish
    isClimbing = true
    timer.start{duration = climbDuration, callback = function() isClimbing = false end}

    -- avoid sending us through the ceiling
    destinationZ = math.min(destinationZ, getCeilingDistance() - mob.height)

    -- trigger the actual climbing function
    local speed = (mob.moveSpeed < 100) and 1.5 or 2.0
    timer.start{
        duration = 1/600,
        iterations = 600/speed,
        callback = function()
            climbPlayer(destinationZ, speed)
        end,
    }

    -- trigger climbing started sound after 0.1s
    playSound{delay = 0.1, sound = 'corpDRAG', volume = 0.6, pitch = 0.8}

    -- trigger climbing finished sound after 0.7s
    playSound{delay = 0.7, sound = 'corpDRAG', volume = 0.3, pitch = 1.3}
end

local function attemptClimbing()
    local destination = getClimbingDestination()
    if destination == nil then
        return
    end

    -- how much to move upwards
    -- bias for player bounding box
    destination = (destination.z - tes3.player.position.z) + 70
    startClimbing(destination)

    if skillModuleClimb ~= nil and config.trainClimbing then
        local climbProgressHeight = math.max(0, tes3.player.position.z)
        climbProgressHeight = math.min(climbProgressHeight, 10000)
        climbProgressHeight = math.remap(climbProgressHeight, 0, 10000, 1, 5)
        -- mwse.log(climbProgressHeight)
        applyClimbingProgress(climbProgressHeight)
    end

    --
    applyAcrobaticsProgress()
    applyAthleticsProgress()
    applyClimbingFatigueCost()

    return true
end

-- luacheck: ignore 212/e
local function onKeyDownJump(e)
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
            applyClimbingProgress(5)
            -- mwse.log("too fast")
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

local isJumpKey = function(keyCode)
    local key = tes3.worldController.inputController.inputMaps[tes3.keybind.jump + 1]
    isJumpKey = function(keyCode) return keyCode == key.code end
    return isJumpKey(keyCode)
end

--
-- Events
--

local function onKeyDown(e)
    if isJumpKey(e.keyCode) then
        onKeyDownJump()
    end
end
event.register('keyDown', onKeyDown)

local function onSkillsReady()
    local charGen = tes3.findGlobal("CharGenState")
    local function checkCharGen()
        if charGen.value ~= -1 then return end
        skillModuleClimb.registerSkill("climbing", {
            name = "Climbing",
            icon = "Icons/vt/climbing.dds",
            description = (
                "Climbing is a skill checked whenever one attempts to scale a wall or a steep incline." ..
                " Skilled individuals can climb longer by getting exhausted later."
            ),
            value = 10,
            attribute =  tes3.attribute.strength,
            specialization = tes3.specialization.stealth,
            active = config.trainClimbing and "active" or "inactive"
        })
        event.unregister("simulate", checkCharGen)
    end
    event.register("simulate", checkCharGen)
end
event.register("OtherSkills:Ready", onSkillsReady)

local function onModConfigReady(e)
    require("mantle.mcm")
end
event.register("modConfigReady", onModConfigReady)
