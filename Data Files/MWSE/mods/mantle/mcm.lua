local config = require("mantle.config")


local template = mwse.mcm.createTemplate{name = "Mantle of Ascension"}
template:saveOnClose("mantle", config)
template:register()

local sideBarDefault = (
        "Mantle of Ascension\n\z" ..
        "Adds Thief style climbing to Morrowind\n\z" ..
        "by Vtastek, Greatness7, Herbert\n\z" ..
        "v0.3\n\z\n\z" ..
        "For climbing to also have its own skill, optionally get:"
    )

local function addSideBar(component)
    component.sidebar:createInfo{ text = sideBarDefault}
    component.sidebar:createHyperLink{
        text = "Skills Module by Merlord",
        exec = "start https://www.nexusmods.com/morrowind/mods/46034",
    }
end

local generalPage = template:createSideBarPage()
addSideBar(generalPage)

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
