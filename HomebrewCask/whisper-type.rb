cask "whisper-type" do
  version "VERSION"
  sha256 "SHA256"

  # TODO: Replace marc1107 with your actual GitHub username
  url "https://github.com/marc1107/whisper-type/releases/download/v#{version}/WhisperType-v#{version}-arm64.dmg"
  name "WhisperType"
  desc "Local speech-to-text dictation for macOS, powered by whisper.cpp"
  homepage "https://github.com/marc1107/whisper-type"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "WhisperType.app"

  postflight do
    # Remind user about permissions
    ohai "WhisperType needs Accessibility and Microphone permissions."
    ohai "Go to: System Settings → Privacy & Security → Accessibility → Enable WhisperType"
  end

  zap trash: [
    "~/Library/Application Support/WhisperType",
    "~/Library/Preferences/com.whispertype.app.plist",
  ]
end
