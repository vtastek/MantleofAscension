local config = require("mantle.config")


local template = mwse.mcm.createTemplate{name = "Mantle of Ascension"}
template:saveOnClose("mantle", config)
template:register()

local generalPage = template:createSideBarPage{
    label = "Mantle of Ascension Settings",
    description = "General settings Mantle of Ascension, v0.0.1",
}

generalPage:createYesNoButton{
    label = "Train Acrobatics",
    description = "Climbing will increase Acrobatics skill...",
    variable = mwse.mcm.createTableVariable({id = "trainAcrobatics", table = config})
}
generalPage:createYesNoButton{
    label = "Train Athletics",
    description = "Climbing will increase Athletics skill...",
    variable = mwse.mcm.createTableVariable({id = "trainAthletics", table = config})
}

generalPage:createYesNoButton{
    label = "Train Climbing",
    description = "Climbing will increase its own Climbing skill...\n\z
        This setting requires the Skills Module to be installed.",
    variable = mwse.mcm.createTableVariable{ id = "trainClimbing", table = config, },
    -- make sure setting can only be enabled if skills module is installed
    callback = function (self)
        
        local value = self.variable.value

        if value and not include("SkillsModule") then
            tes3.messageBox("Error: The Skills Module is not installed!")
            self.variable.value = false
            self:update()
        end
    end
}

generalPage:createYesNoButton{
    label = "Disable Third Person",
    description = "Third Person lacks animations, also Morrowind's janky physics makes it undesirable.",
    variable = mwse.mcm.createTableVariable({id = "disableThirdPerson", table = config})
}

generalPage:createYesNoButton{
    label = "Enable Debug Widgets",
    description = "Debug raycasts with widgets, only enable for debugging.",
    variable = mwse.mcm.createTableVariable({id = "enableDebugWidgets", table = config})
}
