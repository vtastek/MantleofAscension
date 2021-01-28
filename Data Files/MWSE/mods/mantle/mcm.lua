local config = require("mantle.config")

local template = mwse.mcm.createTemplate{name="Mantle of Ascension"}
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
    description = "Climbing will increase Athletics skill... Requires Skill Module",
    variable = mwse.mcm.createTableVariable({id = "trainClimbing", table = config})
}
generalPage:createKeyBinder{
    label = "Climb Button Modifier",
    description = "The key you tap to climb, defaults to jump button",
    allowCombinations = false,
    variable = mwse.mcm.createTableVariable({id = "climbKey", table = config})
}
