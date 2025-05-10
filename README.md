# lrc-ai-describe
Plugin for Lightroom Classic that generates description for photos using Gemini and saves it in the photo's metadata.

To use it:

1. Clone this repo
2. Get an Gemini API key at https://aistudio.google.com/app/apikey 
3. Open Lightroom Classic, go to File > Plug-in Manager > Add, and select the `lrc-ai-describe.lrplugin` folder in this repo
4. Paste the Gemini API key in the settings section, and click "done"
5. Select an image, go to Library > Plug-in Extras > Generate keywords, title and caption with Gemini AI
6. Wait a few seconds, a message will let you know when the alt text has been generated
7. Inspect the caption, title and keywords in the photo's metadata, and edit as needed
