-- mantle v0.2
-- by vtastek
-- Adds climbing to Morrowind

local config = require("mantle.config")
mwse.log("[Mantle of Ascension] initialized v0.0.1")

local skillModuleClimb = include("OtherSkills.skillModule")

-- state
local isClimbing = false

-- constants
local UP = tes3vector3.new(0, 0, 1)
local DOWN = tes3vector3.new(0, 0, -1)

local charGen
local function checkCharGen()
    if charGen.value == -1 then
        event.unregister("simulate", checkCharGen)

        local climbingDescription = (
            "Climbing is a skill checked whenever one attempts to scale a wall or a steep incline." ..
             " Skilled individuals can climb longer by getting exhausted later."
        )
        skillModuleClimb.registerSkill(
            "climbing",
            {
                name = "Climbing",
                icon = "Icons/vt/climbing.dds",
                value = 10,
                attribute =  tes3.attribute.strength,
                description = climbingDescription,
                specialization = tes3.specialization.stealth,
                active = config.trainClimbing and "active" or "inactive"
            }
        )
    end
end

local function onSkillsReady()
    charGen = tes3.findGlobal("CharGenState")
    event.register("simulate", checkCharGen)
end
event.register("OtherSkills:Ready", onSkillsReady)

local function applyClimbingProgress(value)
    skillModuleClimb.incrementSkill( "climbing", {progress = value} )
end

local function applyAthleticsProgress(mob)
    mob:exerciseSkill(tes3.skill.athletics, 0.15)
end

local function applyAcrobaticsProgress(mob)
    mob:exerciseSkill(tes3.skill.acrobatics, 0.15)
end

--
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

-- alternative rayTest function that also places a visualization
local function debugRayTest(t)
    local rayhit = tes3.rayTest(t)
    if t.widgetId and rayhit and config.enableDebugWidgets then
        debugPlaceWidget(t.widgetId, t.position, rayhit.intersection)
    end
    return rayhit
end
---

local function getClimbingDestination()
    local position = tes3.player.position:copy()
    local direction = tes3.getPlayerEyeVector()

    local dirVelocity = 1 + 0.5 * math.min(1, tes3.mobilePlayer.moveSpeed/400)

    -- clear direction z component and re-normalize
    -- this creates a "forward" vector without tilt
    direction.z = 0
    direction:normalize()

    -- get the minimum obstacle height (pc waist)
    local minHeight = position.z + tes3.mobilePlayer.height * 0.5

    -- we do raycasts from 200 units above player
    position.z = position.z + 200

    -- variable for holding the final destination
    local destination = { z = -math.huge }

    -- doing N raycasts of varying amounts forward
    for i, unitsForward in ipairs{
        0.99 * dirVelocity,
        0.86 * dirVelocity,
        0.73 * dirVelocity,
        0.60 * dirVelocity,
        0.47 * dirVelocity,
        0.33
    } do
        local rayhit = debugRayTest{
            widgetId = ("widget_%s"):format(i),
            position = position + (direction * 80 * unitsForward * unitsForward * unitsForward),
            direction = DOWN,
            ignore = {tes3.player},
        }
        if rayhit then
            -- only keep the intersection with highest z
            -- and only if it is higher than the minimum
            if (rayhit.intersection.z > destination.z
                and rayhit.intersection.z > minHeight)
            then
                destination = rayhit.intersection:copy()
            end
        end
    end

    -- if x/y are undefined then all racasts failed
    if destination.x and destination.y then
        return destination
    end
end

local function getCeilingDistance()
    local eyePos = tes3.getPlayerEyePosition()
    local result = tes3.rayTest{position = eyePos, direction = UP, ignore={tes3.player}}
    if result then
        return result.distance
    end
    return math.huge
end

local function climbPlayer(destinationZ, speed)
    -- some bias to prevent clipping through floors
    if getCeilingDistance() >= 20 then
        local mob = tes3.mobilePlayer
        local pos = mob.reference.position

        -- equalizing instead gets consistent results
        local verticalClimb = pos.z + (destinationZ / 600 * speed) - pos.z
        if verticalClimb > 0 then
            pos.z = pos.z + (destinationZ / 600 * speed)
            mob.velocity = tes3vector3.new(0, 0, 0)
        end
    end
end

local function playClimbingStartedSound()
    tes3.playSound{sound = 'corpDRAG', volume = 0.4, pitch = 0.8}
end

local function playClimbingFinishedSound()
    tes3.playSound{sound = 'corpDRAG', volume = 0.1, pitch = 1.3}
end

local function playClimbingInterruptedSound()
    tes3.playSound{sound = 'Item Armor Light Down', volume = 0.3, pitch = 1.3}
end

local function startClimbing(destination, speed, penalty)
    -- trigger the actual climbing function
    timer.start{
        duration=1/600,
        iterations=600/speed,
        callback=function()
            climbPlayer(destination, speed)
        end,
    }

    -- trigger climbing started sound after 0.1s
    timer.start{duration = 0.1, callback = playClimbingStartedSound}
    -- trigger climbing finished sound after 0.7s
    timer.start{duration = 0.7, callback = playClimbingFinishedSound}
    -- clear climbing state after 0.4s
    timer.start{duration = penalty, callback = function() isClimbing = false end}

    --mobilePlayer:exerciseSkill(tes3.skill.acrobatics, 1)
end

-- luacheck: ignore 212/e
local function onClimbE(e)
    local playerMob = tes3.mobilePlayer

    if isClimbing then
        return
    elseif tes3ui.menuMode() then
        return
    elseif tes3.is3rdPerson() and config.disableThirdPerson then
         return
    elseif playerMob.isFlying then
        return
    end

    -- prevent climbing while downed/dying/etc
    local attackState = playerMob.actionData.animationAttackState
    if attackState ~= tes3.animationState.idle then
        return
    end

    -- disable during chargen, -1 is all done
    if tes3.getGlobal('ChargenState') ~= -1 then
        return
    end

    -- if there is enough room for PC height go on
    if getCeilingDistance() < playerMob.height then
        return
    end

        -- falling too fast
    -- acrobatics 25 fastfall 100 -1000
    -- acrobatics 100 fastfall 25 -2000
    local velocity = playerMob.velocity
    local fastfall = 125 - playerMob.acrobatics.current
    if fastfall > 0 then
        if velocity.z < -10 * (-1.5 * fastfall + 250) then
            applyClimbingProgress(5)
            -- mwse.log("too fast")
            return
        end
    end

    -- down raycast
    local destination = getClimbingDestination()
    if (destination == nil) then
        return
    end



    -- let's start! finally...
    local speed = 2.0

    -- stationary penalty
    if (playerMob.moveSpeed) < 100 then
        speed = 1.5
    end

    -- how much to move upwards
    -- bias for player bounding box
    destination = (destination.z - playerMob.position.z) + 70

    local jumpBase = tes3.findGMST('fFatigueJumpBase').value
    local jumpMult = tes3.findGMST('fFatigueJumpMult').value
    local encumbRatio = playerMob.encumbrance.current / playerMob.encumbrance.base

    local skillCheckAverage = 0
    local skillCheckDivider = 0

    if config.trainAcrobatics then
        skillCheckAverage = tes3.mobilePlayer:getSkillValue(tes3.skill.acrobatics)
        skillCheckDivider = 1
    end
    if config.trainAthletics then
        skillCheckAverage = skillCheckAverage + tes3.mobilePlayer:getSkillValue(tes3.skill.athletics)
        skillCheckDivider = skillCheckDivider + 1
    end
    if skillModuleClimb ~= nil and config.trainClimbing then
        skillCheckAverage = skillCheckAverage + skillModuleClimb.getSkill("climbing").value
        skillCheckDivider = skillCheckDivider + 1
    end

    if skillCheckDivider > 0 then
        skillCheckAverage = skillCheckAverage / skillCheckDivider
    end

    skillCheckAverage = math.max(0.1, 1 - skillCheckAverage / 100)

    local fatigueCost = jumpBase + encumbRatio * jumpMult
    fatigueCost = fatigueCost * 2 * skillCheckAverage

    playerMob.fatigue.current = math.max(0, playerMob.fatigue.current - fatigueCost)

    local penalty = 0.4
    if tes3.mobilePlayer.fatigue.current < fatigueCost or encumbRatio > 0.85 then
        destination = destination - playerMob.height * 0.8
        timer.start{duration = 0.8, callback = playClimbingInterruptedSound}
        penalty = 2.0
    end

    isClimbing = true
    startClimbing(destination, speed, penalty)

    -- applyClimbingFatigueCost(tes3.mobilePlayer)

    if skillModuleClimb ~= nil and config.trainClimbing then
        local climbProgressHeight = math.max(0, tes3.player.position.z)
        climbProgressHeight = math.min(climbProgressHeight, 10000)
        climbProgressHeight = math.remap(climbProgressHeight, 0, 10000, 1, 5)
        -- mwse.log(climbProgressHeight)
        applyClimbingProgress(climbProgressHeight)
    end

    if config.trainAcrobatics then
        applyAcrobaticsProgress(tes3.mobilePlayer)
    end
    if config.trainAthletics then
       applyAthleticsProgress(tes3.mobilePlayer)
    end
end

local function isJumpkey(keyCode)
    return keyCode == tes3.worldController.inputController.inputMaps[tes3.keybind.jump+1].code
end

local function onKeyDown(e)
    if not (e.pressed and isJumpkey(e.keyCode)) then
        return
    end
    onClimbE()
end
event.register('keyDown', onKeyDown)

local function registerMCM(e)
    require("mantle.mcm")
end
event.register("modConfigReady", registerMCM)
