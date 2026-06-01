cmake_minimum_required(VERSION 3.5.0)
project(heyvpn)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

add_library(heyvpn SHARED napi_init.cpp)
target_link_libraries(heyvpn PUBLIC libace_napi.z.so libdl.so libhilog_ndk.z.so)

set(HEYVPN_PREBUILT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/arm64-v8a)
foreach(PREBUILT_LIB libxray.so libheytun2socks.so)
    if(EXISTS "${HEYVPN_PREBUILT_DIR}/${PREBUILT_LIB}")
        add_custom_command(TARGET heyvpn POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${HEYVPN_PREBUILT_DIR}/${PREBUILT_LIB}"
            "$<TARGET_FILE_DIR:heyvpn>/${PREBUILT_LIB}")
    endif()
endforeach()
