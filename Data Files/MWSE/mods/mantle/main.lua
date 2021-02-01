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

local function getJumpExperienceValue()
    return tes3.getSkill(tes3.skill.acrobatics).actions[1]
end

local function getJumpFatigueCost()
    local jumpBase = tes3.findGMST('fFatigueJumpBase').value
    local jumpMult = tes3.findGMST('fFatigueJumpMult').value
    local encRatio = tes3.mobilePlayer.encumbrance.current / tes3.mobilePlayer.encumbrance.base
    return jumpBase + encRatio * jumpMult
end

local function getForwardVelocity()
    -- clear direction z component and re-normalize
    -- this creates a "forward" vector without tilt
    local direction = tes3.getPlayerEyeVector()
    direction.z = 0
    direction:normalize()

    local mob = tes3.mobilePlayer
    local velocity = mob.velocity:copy()

    -- velocity is zero when not jumping
    -- so we calculate it from movespeed
    if velocity:length() == 0 then
        if mob.isMovingForward then
            velocity = direction * mob.moveSpeed
        else
            velocity = direction * (mob.isWalking and 100 or 175)
        end
        if mob.isMovingLeft or mob.isMovingRight then
            velocity = velocity * 0.5
        end
    end

    return direction * velocity:dot(direction)
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

local function applyAcrobaticsProgress(mob)
    mob:exerciseSkill(tes3.skill.acrobatics, getJumpExperienceValue())
end

local function applyAthleticsProgress(mob)
    mob:exerciseSkill(tes3.skill.athletics, getJumpExperienceValue())
end

local function applyClimbingProgress(value)
    skillModuleClimb.incrementSkill("climbing", {progress = value})
end

-- place a widget to help visual rayTest results
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
    if rayhit and t.widgetId and config.enableDebugWidgets then
        debugPlaceWidget(t.widgetId, t.position, rayhit.intersection)
    end
    return rayhit
end

-- playSound wrapper that accepts time delay parameter
local function playSound(t)
    if t.delay == nil then
        tes3.playSound(t)
    else
        timer.start{duration = t.delay, callback = function() tes3.playSound(t) end}
    end
end

local function getClimbingDestination()

    -- get the minimum obstacle height (pc waist)
    local position = tes3.player.position:copy()
    local minHeight = position.z + tes3.mobilePlayer.height * 0.5

    -- we do raycasts from 200 units above player
    position.z = position.z + 200

    -- variable for holding the final destination
    local destination = { z = -math.huge }

    -- doing N raycasts of varying amounts forward
    local forwardVelocity = getForwardVelocity()
    for i, step in ipairs{
        0.990,
        0.860,
        0.730,
        0.600,
        0.470,
        0.033 -- first ray does not need to be changed
    } do
        local rayhit = rayTest{
            widgetId = ("widget_%s"):format(i),
            position = position + forwardVelocity * step,
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

    -- if x/y are undefined then all raycasts failed
    if destination.x and destination.y then
        return destination
    end
end

local function getCeilingDistance()
    local eyePos = tes3.getPlayerEyePosition()
    local result = tes3.rayTest{position = eyePos, direction = UP, ignore = {tes3.player}}
    if result then
        return result.distance
    end
    return math.huge
end

local function climbPlayer(destinationZ, speed)
    -- some bias to prevent clipping through floors
    if getCeilingDistance() < 20 then return end

    local mob = tes3.mobilePlayer
    local pos = mob.reference.position

    -- equalizing instead gets consistent results
    local verticalClimb = pos.z + (destinationZ / 600 * speed) - pos.z
    if verticalClimb > 0 then
        pos.z = pos.z + (destinationZ / 600 * speed)
        mob.velocity = tes3vector3.new(0, 0, 0)
    end
end

local function startClimbing(destination)
    local mob = tes3.mobilePlayer

    -- trigger the actual climbing function
    local speed = (mob.moveSpeed < 100) and 1.5 or 2.0
    timer.start{
        duration = 1/600,
        iterations = 600/speed,
        callback = function()
            climbPlayer(destination, speed)
        end,
    }

    -- trigger climbing started sound after 0.1s
    playSound{delay = 0.1, sound = 'corpDRAG', volume = 0.4, pitch = 0.8}

    -- trigger climbing finished sound after 0.7s
    playSound{delay = 0.7, sound = 'corpDRAG', volume = 0.1, pitch = 1.3}

    -- clear climbing state after 0.4s
    local penalty = 0.4
    local encumbRatio = mob.encumbrance.current / mob.encumbrance.base
    if (mob.fatigue.current <= 0) or (encumbRatio > 0.85) then
        destination = destination - mob.height * 0.8
        playSound{delay = 0.8, sound = 'Item Armor Light Down', volume = 0.3, pitch = 1.3}
        penalty = 2.0
    end
    isClimbing = true
    timer.start{duration = penalty, callback = function() isClimbing = false end}
end

-- luacheck: ignore 212/e
local function onKeyDownJump(e)
    local mob = tes3.mobilePlayer

    if isClimbing then
        return
    elseif mob.isFlying then
        return
    elseif tes3ui.menuMode() then
        return
    elseif tes3.is3rdPerson() and config.disableThirdPerson then
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

    -- if there is enough room for PC height go on
    if getCeilingDistance() < mob.height then
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

    -- down raycast
    local destination = getClimbingDestination()
    if (destination == nil) then
        return
    end

    --
    applyClimbingFatigueCost()

    -- how much to move upwards
    -- bias for player bounding box
    destination = (destination.z - mob.position.z) + 70
    startClimbing(destination)

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

-- events
local function registerMCM(e)
    require("mantle.mcm")
end
event.register("modConfigReady", registerMCM)

local function onSkillsReady()
    local charGen = tes3.findGlobal("CharGenState")
    local function checkCharGen()
        if charGen.value ~= -1 then return end
        skillModuleClimb.registerSkill(
            "climbing",
            {
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
            }
        )
        event.unregister("simulate", checkCharGen)
    end
    event.register("simulate", checkCharGen)
end
event.register("OtherSkills:Ready", onSkillsReady)

local jumpKey
event.register("initialized", function()
    jumpKey = tes3.worldController.inputController.inputMaps[tes3.keybind.jump + 1]
end)

local function onKeyDown(e)
    if e.pressed and (e.keyCode == jumpKey.code) then
        onKeyDownJump()
    end
end
event.register('keyDown', onKeyDown)
