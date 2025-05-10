return {
  LrSdkVersion = 6.0,
  LrSdkMinimumVersion = 6.0,
  LrPluginName = "AI Describe",
  LrToolkitIdentifier = "com.example.lightroom.aidesribe",
  LrPluginInfoUrl = "https://github.com/melastmohican/lrc-ai-describe",
  LrInitPlugin = "AIDescribe.lua",
  LrLibraryMenuItems = {
    {
      title = "Generate keywords, title and caption with Gemini AI",
      file = "AIDescribe.lua",
    },
  },
  LrPluginInfoProvider = 'PluginInfoProvider.lua',
  VERSION = { major = 14, minor = 3, revision = 0, build = 200000, },
}
