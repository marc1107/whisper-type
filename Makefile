.PHONY: build run clean whisper xcode test integration-test

# Build whisper.cpp static libraries
whisper:
	cd whisper.cpp && cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_METAL=ON -DWHISPER_COREML=OFF -DBUILD_SHARED_LIBS=OFF
	cd whisper.cpp && cmake --build build --config Release -j$$(sysctl -n hw.ncpu)

# Generate Xcode project
xcode: whisper
	xcodegen generate

# Build the app via xcodebuild
build: xcode
	xcodebuild -project WhisperType.xcodeproj -scheme WhisperType -configuration Release build

# Run the built app
run:
	open build/Release/WhisperType.app || open DerivedData/WhisperType/Build/Products/Release/WhisperType.app

# Run tests
test: xcode
	xcodebuild -project WhisperType.xcodeproj -scheme WhisperTypeTests test

# Run only the local Ollama integration test suite. Skips itself if Ollama
# is not reachable on localhost:11434, so it's a no-op on machines without
# Ollama installed (CI never runs this target).
integration-test: xcode
	xcodebuild -project WhisperType.xcodeproj -scheme WhisperTypeTests \
		-only-testing:WhisperTypeTests/LLMOllamaIntegrationTests test

clean:
	rm -rf DerivedData build
	cd whisper.cpp && rm -rf build
