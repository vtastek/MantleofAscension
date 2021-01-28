-- mantle v0.1
-- by vtastek
-- Adds climbing to Morrowind

local climbHeight = 0
local jumpPosition = 0
local cSpeed = 2.0
-- local jumpingState

local jumping = nil
-- local holding = nil

local acroInf = 1 -- acrobatics influence todo
local FatigInf = 1 -- Fatigue influence todo

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

local function getCeilingHeight()
    local eyePos = tes3.getPlayerEyePosition()
    local result = tes3.rayTest{position = eyePos, direction = UP}
    if result then
        return result.intersection.z
    else
        return eyePos.z + 1000
    end
end

local function applyClimbingFatigueCost(mobile)
    local jumpBase = tes3.findGMST('fFatigueJumpBase').value
    local jumpMult = tes3.findGMST('fFatigueJumpMult').value
    local encumbRatio = mobile.encumbrance.current / mobile.encumbrance.base
    local fatigueCost = jumpBase + encumbRatio * jumpMult
    mobile.fatigue.current = math.max(0, mobile.fatigue.current - fatigueCost)
end

local function climbPlayer()
    -- some bias to prevent clipping through floors
    if (getCeilingHeight() < (tes3.getPlayerEyePosition().z + 20)) then
        return
    end

    local playerMob = tes3.mobilePlayer

    -- if added directly, it will fight gravity badly
    jumpPosition = jumpPosition + climbHeight / 60 * cSpeed * FatigInf

    -- equalizing instead gets consistent results
    playerMob.reference.position.z = jumpPosition

    -- tiny amount of velocity cancellation
    -- not zero, zero disables gravity impact
    playerMob.velocity.x = 0.01
    playerMob.velocity.y = 0.01
    playerMob.velocity.z = 0.01
    playerMob.impulseVelocity.x = 0.01
    playerMob.impulseVelocity.y = 0.01
    playerMob.impulseVelocity.z = 0.01
end

local function playClimbingStartedSound()
    tes3.playSound{sound = 'corpDRAG', volume = 0.4, pitch = 0.8}
end

local function playClimbingFinishedSound()
    tes3.playSound{sound = 'corpDRAG', volume = 0.1, pitch = 1.3}
end

local function onClimbE(e)
    -- disabled during jumping, by jumping I mean climbing
    if (jumping == 1) then
        return
    elseif tes3ui.menuMode() then
        return
    elseif tes3.is3rdPerson() then
        return
    elseif tes3.mobilePlayer.isFlying then
        return
    end

    -- prevent climbing while downed/dying/etc
    local attackState = tes3.mobilePlayer.actionData.animationAttackState
    if attackState ~= tes3.animationState.idle then
        return
    end

    -- disable during chargen, -1 is all done
    if (tes3.getGlobal('ChargenState') ~= -1) then
        return
    end

    -- down raycast
    local result = frontDownCast()
    if (result == nil) then
        return
    end

    -- if there is enough room for PC height go on
    local pHeight = tes3.mobilePlayer.height
    if (getCeilingHeight() - result.intersection.z) < pHeight then
        return
    end

    -- if below waist obstacle, do not attempt climbing
    if result.intersection.z < (tes3.getPlayerEyePosition().z - (pHeight * 0.5)) then
        return
    end

    -- let's start! finally...
    local velPlayer = tes3.mobilePlayer.velocity
    local velCurrent = math.abs(velPlayer.x) + math.abs(velPlayer.y)

    -- stationary penalty
    if (velCurrent < 100) then
        cSpeed = 1.5
    end

    -- falling too fast
    -- acrobatics 25 fastfall 100 -1000
    -- acrobatics 100 fastfall 25 -2000
    local fastfall = math.max(0, 125 - tes3.mobilePlayer.acrobatics.current)
    if (fastfall ~= 0) then
        if (velPlayer.z < -10 * (-1.5 * fastfall + 250)) then
            return
        end
    end

    -- how much to move upwards
    -- bias for player bounding box
    climbHeight = (result.intersection.z - tes3.player.position.z) * acroInf + 70

    if (tes3.player.position.z < result.intersection.z) then
        jumpPosition = tes3.player.position.z
        jumping = 1

        timer.start(1 / 60, climbPlayer, 60 / cSpeed)
        applyClimbingFatigueCost(tes3.mobilePlayer)

        --mobilePlayer:exerciseSkill(tes3.skill.acrobatics, 1)

        timer.start(0.1, playClimbingStartedSound)
        timer.start(0.7, playClimbingFinishedSound)
        timer.start(0.4, function() jumping = 0 end)
    end
end
event.register('keyDown', onClimbE, {filter = tes3.scanCode.e})
