cmake_minimum_required(VERSION 3.22)
project(nexterm_jni C)

set(FREERDP_SRC   "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../freerdp_src")
set(FREERDP_BUILD "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../freerdp_build/${ANDROID_ABI}")
set(OPENSSL_INC   "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../android_openssl/ssl_3/include")

include_directories(
    ${FREERDP_SRC}/include
    ${FREERDP_SRC}/winpr/include
    ${FREERDP_BUILD}/include
    ${FREERDP_BUILD}/winpr/include
    ${OPENSSL_INC}
)

set(JNILIBS "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")

add_library(freerdp3        SHARED IMPORTED)
add_library(freerdp-client3 SHARED IMPORTED)
add_library(winpr3          SHARED IMPORTED)
set_target_properties(freerdp3        PROPERTIES IMPORTED_LOCATION "${JNILIBS}/libfreerdp3.so")
set_target_properties(freerdp-client3 PROPERTIES IMPORTED_LOCATION "${JNILIBS}/libfreerdp-client3.so")
set_target_properties(winpr3          PROPERTIES IMPORTED_LOCATION "${JNILIBS}/libwinpr3.so")

add_library(nexterm_jni SHARED nexterm_jni.c)
target_link_libraries(nexterm_jni freerdp3 freerdp-client3 winpr3 android log)
