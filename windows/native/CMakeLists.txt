cmake_minimum_required(VERSION 3.20)
project(nexterm_rdp C)

set(FREERDP_BUILD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../freerdp_build/win64")
set(FREERDP_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../freerdp_src")

add_library(nexterm_rdp SHARED nexterm_rdp.c)

target_compile_definitions(nexterm_rdp PRIVATE NEXTERM_RDP_EXPORTS WIN32_LEAN_AND_MEAN)

target_include_directories(nexterm_rdp PRIVATE
    "${FREERDP_SRC_DIR}/include"
    "${FREERDP_SRC_DIR}/winpr/include"
    "${FREERDP_BUILD_DIR}/include"
    "${FREERDP_BUILD_DIR}/winpr/include"
)

target_link_directories(nexterm_rdp PRIVATE
    "${FREERDP_BUILD_DIR}/libfreerdp/Release"
    "${FREERDP_BUILD_DIR}/client/common/Release"
    "${FREERDP_BUILD_DIR}/winpr/libwinpr/Release"
)

target_link_libraries(nexterm_rdp PRIVATE
    freerdp3
    freerdp-client3
    winpr3
    ws2_32
)
