local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrFileUtils = import 'LrFileUtils'
local LrExportSession = import 'LrExportSession'
local LrStringUtils = import 'LrStringUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrLogger = import 'LrLogger'

local logger = LrLogger('AIDescribePlugin')
logger:enable("logfile")

--local LrMobdebug = import 'LrMobdebug' -- Import LR/ZeroBrane debug module

--LrMobdebug.start()

local configPath = LrPathUtils.child(_PLUGIN.path, 'config.lua')
local config = dofile(configPath)
local prefs = LrPrefs.prefsForPlugin()
local dkjsonPath = LrPathUtils.child(_PLUGIN.path, 'dkjson.lua')
local json = dofile(dkjsonPath)

local function resizePhoto(photo, progressScope)
    progressScope:setCaption("Resizing photo...")
    local tempDir = LrPathUtils.getStandardFilePath('temp')
    local photoName = LrPathUtils.leafName(photo:getFormattedMetadata('fileName'))
    local resizedPhotoPath = LrPathUtils.child(tempDir, photoName)

    if LrFileUtils.exists(resizedPhotoPath) then
        return nil
    end

    local exportSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = tempDir,
        LR_export_useSubfolder = false,
        LR_format = 'JPEG',
        LR_jpeg_quality = 0.8,
        LR_minimizeEmbeddedMetadata = true,
        LR_outputSharpeningOn = false,
        LR_size_doConstrain = true,
        LR_size_maxHeight = 2000,
        LR_size_maxWidth = 2000,
        LR_size_resizeType = 'wh',
        LR_size_units = 'pixels',
    }

    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings
    })

    for _, rendition in exportSession:renditions() do
        local success, path = rendition:waitForRender()
        if success then
            return path
        end
    end

    return nil
end

local function encodePhotoToBase64(filePath, progressScope)
    progressScope:setCaption("Encoding photo...")

    local file = io.open(filePath, "rb")
    if not file then
        return nil
    end

    local data = file:read("*all")
    file:close()

    return LrStringUtils.encodeBase64(data)
end

local function buildPayload(imageBase64)
    return json.encode({
        contents = {
            {
                role = "user",
                parts = {
                    { text = config.PROMPT_TEXT },
                    {
                        inlineData = {
                            mimeType = "image/jpeg",
                            data = imageBase64
                        }
                    }
                }
            }
        },
        generationConfig = {
            temperature = 1,
            topP = 0.95,
            maxOutputTokens = 8192,
            responseModalities = { "TEXT" }
        },
        safetySettings = {
            { category = "HARM_CATEGORY_HATE_SPEECH",       threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HARASSMENT",        threshold = "BLOCK_NONE" }
        }
    })
end

local function requestDescriptionForPhoto(imageBase64, progressScope)
    local apiKey = prefs.geminiApiKey
    progressScope:setCaption("Generating description...")

    local response = {}
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-001:streamGenerateContent?key=" ..
        apiKey
    local headers = {
        { field = "Content-Type", value = "application/json" },
    }

    local payload = buildPayload(imageBase64)
    local response, _ = LrHttp.post(url, payload, headers)

    local ok, decoded = pcall(json.decode, response)
    if not ok then
        logger:trace("Failed to parse Gemini response: " .. tostring(response))
        LrDialogs.message("Invalid response from Gemini.")
        return nil
    end

    local combined_text = ""

    for _, item in ipairs(decoded) do
        if item.candidates and item.candidates[1] and item.candidates[1].content and item.candidates[1].content.parts then
            local parts = item.candidates[1].content.parts
            for _, part in ipairs(parts) do
                if part.text then
                    combined_text = combined_text .. part.text
                end
            end
        end
    end

    -- Response is in Markdown format, so we need to clean it up
    combined_text = string.gsub(combined_text, '```json', '')
    combined_text = string.gsub(combined_text, '```', '')
    return json.decode(combined_text)
end

local function generateDescriptionForPhoto(photo, progressScope)
    local fileName = photo:getFormattedMetadata('fileName')
    local resizedFilePath = resizePhoto(photo, progressScope)
    if not resizedFilePath then
        return false
    end

    local base64Image = encodePhotoToBase64(resizedFilePath, progressScope)
    if not base64Image then
        return false
    end

    LrFileUtils.delete(resizedFilePath)

    local response = requestDescriptionForPhoto(base64Image, progressScope)

    if response then
        logger:info("Response: " .. table.concat(response))
        if response.title then
            local title = response.title
            photo.catalog:withWriteAccessDo("Set Title", function()
                photo:setRawMetadata('title', title)
            end)
        end
        if response.caption then
            local caption = response.caption
            photo.catalog:withWriteAccessDo("Set Caption", function()
                photo:setRawMetadata('caption', caption)
            end)
        end
        if response.keywords then
            local keywords = response.keywords
            photo.catalog:withWriteAccessDo("Set Keywords", function()
                for word in string.gmatch(keywords, '([^,]+)') do
                    LrStringUtils.trimWhitespace(word)
                    if word ~= "" then
                        logger:info("Adding keyword: " .. word)
                        local keyword = photo.catalog:createKeyword(word, {}, true, nil, true)
                        if keyword then
                            photo:addKeyword(keyword)
                        end
                    end
                end
            end)
        end
        LrDialogs.showBezel("Description for" .. fileName .. " generated and saved.")
        return true
    end

    return false
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("GenerateDescription", function(context)
        --LrMobdebug.on() -- Make this coroutine known to ZBS
        local catalog = LrApplication.activeCatalog()
        local selectedPhotos = catalog:getTargetPhotos()

        if #selectedPhotos == 0 then
            LrDialogs.message("Please select at least one photo.")
            return
        end

        local progressScope = LrProgressScope({
            title = "Generating Description",
            functionContext = context,
        })

        for i, photo in ipairs(selectedPhotos) do
            progressScope:setPortionComplete(i - 1, #selectedPhotos)
            if not generateDescriptionForPhoto(photo, progressScope) then
                break
            end
            progressScope:setPortionComplete(i, #selectedPhotos)
        end

        progressScope:done()
    end)
end)
