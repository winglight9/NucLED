SDKROOT := $(shell xcrun --show-sdk-path --sdk macosx)
CXX := $(shell xcrun --find clang++)
HEADERS := $(SDKROOT)/System/Library/Frameworks/Kernel.framework/Headers
BUILD_DIR ?= .build
MACOS_VERSION ?= 15.5
OBJECTS := $(BUILD_DIR)/NUCLEDDriver.o $(BUILD_DIR)/NUCLEDUserClient.o $(BUILD_DIR)/KmodInfo.o
KEXT_DIR := $(BUILD_DIR)/NUCLEDDriver.kext
KEXT_EXECUTABLE := $(KEXT_DIR)/Contents/MacOS/NUCLEDDriver

CXXFLAGS := -std=c++17 -fno-exceptions -fno-rtti -fapple-kext -arch x86_64 \
	-isysroot "$(SDKROOT)" -I "$(HEADERS)" -Wall -Wextra -Werror=return-type

.PHONY: all objects bundle check-sdk clean

# Build a local x86_64 kext bundle. This does not install or load it.
all: bundle

objects: check-sdk $(OBJECTS)

bundle: check-sdk $(KEXT_EXECUTABLE) $(KEXT_DIR)/Contents/Info.plist

check-sdk:
	@test -f "$(HEADERS)/IOKit/acpi/IOACPIPlatformDevice.h" || { \
		echo "Kernel ACPI headers not found in SDK: $(HEADERS)" >&2; exit 1; }
	@test -f "$(HEADERS)/IOKit/IOUserClient.h" || { \
		echo "Kernel IOUserClient header not found in SDK: $(HEADERS)" >&2; exit 1; }

$(BUILD_DIR):
	mkdir -p "$@"

$(BUILD_DIR)/NUCLEDDriver.o: NUCLEDDriver/NUCLEDDriver.cpp NUCLEDDriver/NUCLEDDriver.hpp NUCLEDDriver/NUCLEDUserClient.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c "$<" -o "$@"

$(BUILD_DIR)/NUCLEDUserClient.o: NUCLEDDriver/NUCLEDUserClient.cpp NUCLEDDriver/NUCLEDUserClient.hpp NUCLEDDriver/NUCLEDDriver.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c "$<" -o "$@"

$(BUILD_DIR)/KmodInfo.o: NUCLEDDriver/KmodInfo.cpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c "$<" -o "$@"

$(KEXT_EXECUTABLE): $(OBJECTS)
	mkdir -p "$(dir $@)"
	$(CXX) -arch x86_64 -nostdlib -fapple-kext -isysroot "$(SDKROOT)" \
		-mmacosx-version-min=$(MACOS_VERSION) $(OBJECTS) -Wl,-r -Wl,-kext \
		-L "$(SDKROOT)/usr/lib" -lkmodc++ -lkmod -o "$@"

$(KEXT_DIR)/Contents/Info.plist: NUCLEDDriver/Info.plist
	mkdir -p "$(dir $@)"
	cp "$<" "$@"

clean:
	rm -rf "$(BUILD_DIR)"
