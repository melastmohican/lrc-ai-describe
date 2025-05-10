local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'
local LrBinding = import 'LrBinding'

local prefs = LrPrefs.prefsForPlugin()

return {
    sectionsForTopOfDialog = function(f)
        local bind = LrView.bind
        local share = LrView.share

        return {
            {
                title = "AI Describe Settings",
                f:row {
                    f:static_text {
                        title = "Gemini API Key:",
                        alignment = 'right',
                        width = share 'label_width',
                    },
                    f:edit_field {
                        value = bind { key = 'geminiApiKey', object = prefs },
                        width_in_chars = 50,
                    },
                },
            },
        }
    end,
}
