cmake_minimum_required(VERSION 3.14)
project(MicNoiseGateDriver VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")

# Download and configure libASPL
include(FetchContent)
FetchContent_Declare(
    libASPL
    GIT_REPOSITORY https://github.com/gavv/libASPL.git
    GIT_TAG main
)
FetchContent_MakeAvailable(libASPL)

# Driver source files
set(DRIVER_SOURCES
    Driver.cpp
)

# Create the driver bundle
add_library(MicNoiseGateDriver MODULE ${DRIVER_SOURCES})

# Link with libASPL and CoreAudio frameworks
target_link_libraries(MicNoiseGateDriver
    PRIVATE
    libASPL
    "-framework CoreAudio"
    "-framework CoreFoundation"
    "-framework AudioToolbox"
)

# Include headers from libASPL
target_include_directories(MicNoiseGateDriver
    PRIVATE
    ${libaspl_SOURCE_DIR}/include
)

# Set bundle properties
set_target_properties(MicNoiseGateDriver PROPERTIES
    BUNDLE TRUE
    BUNDLE_EXTENSION "driver"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    MACOSX_BUNDLE_BUNDLE_NAME "MicNoiseGate"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.micnoisegate.driver"
    OUTPUT_NAME "MicNoiseGate"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# Install target
install(TARGETS MicNoiseGateDriver
    LIBRARY DESTINATION "/Library/Audio/Plug-Ins/HAL"
    BUNDLE DESTINATION "/Library/Audio/Plug-Ins/HAL"
)
