cmake_minimum_required(VERSION 3.5.0)
project(heyvpn)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

set(HEYVPN_PREBUILT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/arm64-v8a)

add_library(heyvpn SHARED napi_init.cpp)
target_include_directories(heyvpn PRIVATE "${HEYVPN_PREBUILT_DIR}")
target_link_libraries(heyvpn PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libdl.so)

# [SING-BOX SPIKE — TEMP] libsingbox.so 由 scripts/build_libsingbox_ohos.sh 产出；
# if(EXISTS) 守卫保证它还没编出来时不影响正常构建。验证完连同 napi 的临时导出一起删。
foreach(PREBUILT_LIB libxray.so libsingbox.so libheytun2socks.so libhevsocks5tun.so)
    if(EXISTS "${HEYVPN_PREBUILT_DIR}/${PREBUILT_LIB}")
        add_custom_command(TARGET heyvpn POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${HEYVPN_PREBUILT_DIR}/${PREBUILT_LIB}"
            "$<TARGET_FILE_DIR:heyvpn>/${PREBUILT_LIB}")
    endif()
endforeach()
