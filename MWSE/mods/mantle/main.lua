-- mantle v0.1
-- by vtastek
-- Adds climbing to Morrowind

-- config
local acrobaticsInfluence = 1.0 -- TODO
local fatigueInfluence = 1.0 -- TODO

-- state
local isClimbing = false

-- constants
local UP = tes3vector3.new(0, 0, 1)
local DOWN = tes3vector3.new(0, 0, -1)

-- get the ray start pos, from above and slightly front downwards
local function frontDownCast()
    local eyeVec = tes3.getPlayerEyeVector()
    local eyePos = tes3.getPlayerEyePosition()

    -- renormalize eyevec with fixed magnitude for zero z
    -- to avoid making a spherical reach
    local vm = math.sqrt(eyeVec.x * eyeVec.x + eyeVec.y * eyeVec.y)
    if vm <= 0 then
        vm = 1
    end

    local pos = tes3vector3.new(
        eyePos.x + (eyeVec.x / vm * 75),
        eyePos.y + (eyeVec.y / vm * 75),
        eyePos.z + (200)
    )

    return tes3.rayTest{position = pos, direction = DOWN}
end

local function getCeilingDistance()
    local eyePos = tes3.getPlayerEyePosition()
    local result = tes3.rayTest{position = eyePos, direction = UP}
    if result then
        return result.distance
    end
    return math.huge
end

local function applyClimbingFatigueCost(mob)
    local jumpBase = tes3.findGMST('fFatigueJumpBase').value
    local jumpMult = tes3.findGMST('fFatigueJumpMult').value
    local encumbRatio = mob.encumbrance.current / mob.encumbrance.base
    local fatigueCost = jumpBase + encumbRatio * jumpMult
    mob.fatigue.current = math.max(0, mob.fatigue.current - fatigueCost)
end

local function climbPlayer(currentZ, destinationZ, speed)
    -- some bias to prevent clipping through floors
    if getCeilingDistance() < 20 then
        return
    end

    -- equalizing instead gets consistent results
    tes3.player.position.z = currentZ + (destinationZ / 60 * speed * fatigueInfluence)

    -- tiny amount of velocity cancellation
    -- not zero, it disables gravity impact
    tes3.mobilePlayer.velocity = tes3vector3.new(0.01, 0.01, 0.01)
    tes3.mobilePlayer.impulseVelocity = tes3vector3.new(0.01, 0.01, 0.01)

    return tes3.player.position.z
end

local function playClimbingStartedSound()
    tes3.playSound{sound = 'corpDRAG', volume = 0.4, pitch = 0.8}
end

local function playClimbingFinishedSound()
    tes3.playSound{sound = 'corpDRAG', volume = 0.1, pitch = 1.3}
end

local function startClimbing(destination, speed)
    applyClimbingFatigueCost(tes3.mobilePlayer)

    -- trigger the actual climbing function
    local current = tes3.player.position.z
    timer.start{
        duration=1/60,
        iterations=60/speed,
        callback=function()
            current = climbPlayer(current, destination, speed)
        end,
    }

    -- trigger climbing started sound after 0.1s
    timer.start{duration = 0.1, callback = playClimbingStartedSound}
    -- trigger climbing finished sound after 0.7s
    timer.start{duration = 0.7, callback = playClimbingFinishedSound}
    -- clear climbing state after 0.4s
    timer.start{duration = 0.4, callback = function() isClimbing = false end}

    --mobilePlayer:exerciseSkill(tes3.skill.acrobatics, 1)
end

local function onClimbE(e)
    local playerMob = tes3.mobilePlayer

    if isClimbing then
        return
    elseif tes3ui.menuMode() then
        return
    elseif tes3.is3rdPerson() then
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

    -- down raycast
    local destRayHit = frontDownCast()
    if (destRayHit == nil) then
        return
    end

    -- bail if already higher than destination
    local zPos = playerMob.position.z
    if zPos >= destRayHit.intersection.z then
        return
    end

    -- if there is enough room for PC height go on
    if getCeilingDistance() < playerMob.height then
        return
    end

    -- if below waist obstacle, do not attempt climbing
    local waistHeight = playerMob.height * 0.5
    if destRayHit.intersection.z < (zPos + waistHeight) then
        return
    end

    -- falling too fast
    -- acrobatics 25 fastfall 100 -1000
    -- acrobatics 100 fastfall 25 -2000
    local velocity = playerMob.velocity
    local fastfall = 125 - playerMob.acrobatics.current
    if fastfall > 0 then
        if velocity.z < -10 * (-1.5 * fastfall + 250) then
            return
        end
    end

    -- let's start! finally...
    local speed = 2.0

    -- stationary penalty
    if (math.abs(velocity.x) + math.abs(velocity.y)) < 100 then
        speed = 1.5
    end

    -- how much to move upwards
    -- bias for player bounding box
    local destination = (destRayHit.intersection.z - zPos) * acrobaticsInfluence + 70
    startClimbing(destination, speed)
end
event.register('keyDown', onClimbE, {filter = tes3.scanCode.e})
