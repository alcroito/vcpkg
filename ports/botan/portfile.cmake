include(vcpkg_common_functions)

set(BOTAN_VERSION 2.11.0)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO randombit/botan
    REF 16a726c3ad10316bd8d37b6118a5cc52894e8e8f
    SHA512 3d759fb262d65f7d325a1e888f74cb1c372ef687b0fcc6fc6ba041b83e3dc65c2928b343c65a89e73ea00c09d11cdda3a161ca98dbabe426903c4cbaf030767c
    HEAD_REF master
)

if(CMAKE_HOST_WIN32)
    vcpkg_find_acquire_program(JOM)
    set(build_tool "${JOM}")
    set(parallel_build "/J${VCPKG_CONCURRENCY}")
else()
    find_program(MAKE make)
    set(build_tool "${MAKE}")
    set(parallel_build "-j${VCPKG_CONCURRENCY}")
endif()

vcpkg_find_acquire_program(PYTHON3)
get_filename_component(PYTHON3_DIR "${PYTHON3}" DIRECTORY)
set(ENV{PATH} "$ENV{PATH};${PYTHON3_DIR}")

if(VCPKG_LIBRARY_LINKAGE STREQUAL dynamic)
    set(BOTAN_FLAG_SHARED --enable-shared-library)
    set(BOTAN_FLAG_STATIC --disable-static-library)
else()
    set(BOTAN_FLAG_SHARED --disable-shared-library)
    set(BOTAN_FLAG_STATIC --enable-static-library)
endif()

if(VCPKG_CRT_LINKAGE STREQUAL dynamic)
    set(BOTAN_MSVC_RUNTIME "--msvc-runtime=MD")
else()
    set(BOTAN_MSVC_RUNTIME "--msvc-runtime=MT")
endif()

if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
    set(BOTAN_FLAG_CPU x86)
elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
    set(BOTAN_FLAG_CPU x86_64)
elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
    set(BOTAN_FLAG_CPU "armv8-a")
else()
    message(FATAL_ERROR "Unsupported architecture")
endif()

if(VCPKG_CMAKE_SYSTEM_NAME STREQUAL Android)
    if(NOT DEFINED ENV{ANDROID_NDK_HOME})
        message(FATAL_ERROR "Please set environment variable ANDROID_NDK_HOME to point to the "
                "Android NDK location.")
    endif()
    set(ANDROID_TOOLCHAIN_LOCATION
        "$ENV{ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/darwin-x86_64/bin")
    if(NOT EXISTS "${ANDROID_TOOLCHAIN_LOCATION}")
        message(FATAL_ERROR "Can't find Android toolchain at:"
                "$ENV{ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/darwin-x86_64/bin")
    endif()
    set(BOTAN_FLAG_OS "--os=android")

    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        set(BOTAN_CXX_BINARY "--cc-bin=${ANDROID_TOOLCHAIN_LOCATION}/i686-linux-android29-clang++")
        set(BOTAN_AR_BINARY "--ar-command=${ANDROID_TOOLCHAIN_LOCATION}/i686-linux-android-ar")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(BOTAN_CXX_BINARY "--cc-bin=${ANDROID_TOOLCHAIN_LOCATION}/aarch64-linux-android29-clang++")
        set(BOTAN_AR_BINARY "--ar-command=${ANDROID_TOOLCHAIN_LOCATION}/aarch64-linux-android-ar")
    else()
        message(FATAL_ERROR "Unsupported Android architecture")
    endif()
elseif(VCPKG_CMAKE_SYSTEM_NAME STREQUAL iOS)
    set(BOTAN_FLAG_OS "--os=ios")
    list(APPEND BOTAN_EXTRA_CONFIGURE_FLAGS "--cc=clang")

    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        list(APPEND BOTAN_EXTRA_CONFIGURE_FLAGS "--cc-abi-flags=-arch x86_64")
        set(pre_build_tool xcrun --sdk iphonesimulator)
    endif()

    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        list(APPEND BOTAN_EXTRA_CONFIGURE_FLAGS "--cc-abi-flags=-arch arm64")
        set(pre_build_tool xcrun --sdk iphoneos)
    endif()
endif()

list(APPEND BOTAN_EXTRA_CXX_FLAGS "--extra-cxxflags=-fPIC")

function(BOTAN_BUILD BOTAN_BUILD_TYPE)

    if(BOTAN_BUILD_TYPE STREQUAL "dbg")
        set(BOTAN_FLAG_PREFIX ${CURRENT_PACKAGES_DIR}/debug)
        set(BOTAN_FLAG_DEBUGMODE --debug-mode)
        set(BOTAN_DEBUG_SUFFIX "")
        set(BOTAN_MSVC_RUNTIME_SUFFIX "d")
    else()
        set(BOTAN_FLAG_DEBUGMODE)
        set(BOTAN_FLAG_PREFIX ${CURRENT_PACKAGES_DIR})
        set(BOTAN_MSVC_RUNTIME_SUFFIX "")
    endif()

    message(STATUS "Configure ${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE}")

    if(EXISTS ${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE})
        file(REMOVE_RECURSE ${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE})
    endif()
    make_directory(${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE})

    set(configure_arguments "--cpu=${BOTAN_FLAG_CPU}"
                            ${BOTAN_FLAG_SHARED}
                            ${BOTAN_FLAG_STATIC}
                            ${BOTAN_FLAG_DEBUGMODE}
                            ${BOTAN_FLAG_OS}
                            ${BOTAN_CXX_BINARY}
                            ${BOTAN_AR_BINARY}
                            ${BOTAN_EXTRA_CXX_FLAGS}
                            ${BOTAN_EXTRA_CONFIGURE_FLAGS}
                            "--distribution-info=vcpkg ${TARGET_TRIPLET}"
                            --prefix=${BOTAN_FLAG_PREFIX}
                            --link-method=copy)
    if(CMAKE_HOST_WIN32)
        list(APPEND configure_arguments ${BOTAN_MSVC_RUNTIME}${BOTAN_MSVC_RUNTIME_SUFFIX})
    endif()

    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" "${SOURCE_PATH}/configure.py" ${configure_arguments}
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE}"
        LOGNAME configure-${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE})
    message(STATUS "Configure ${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE} done")

    message(STATUS "Build ${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE}")
    vcpkg_execute_build_process(
        COMMAND ${pre_build_tool} "${build_tool}" ${parallel_build}
        NO_PARALLEL_COMMAND ${pre_build_tool} "${build_tool}"
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE}"
        LOGNAME build-${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE})
    message(STATUS "Build ${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE} done")

    message(STATUS "Package ${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE}")
    vcpkg_execute_required_process(
        COMMAND "${PYTHON3}" "${SOURCE_PATH}/src/scripts/install.py"
            --prefix=${BOTAN_FLAG_PREFIX}
            --docdir=share
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE}"
        LOGNAME install-${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE})

    if(VCPKG_LIBRARY_LINKAGE STREQUAL dynamic AND CMAKE_HOST_WIN32)
        file(RENAME ${BOTAN_FLAG_PREFIX}/lib/botan${BOTAN_DEBUG_SUFFIX}.dll ${BOTAN_FLAG_PREFIX}/bin/botan${BOTAN_DEBUG_SUFFIX}.dll)
    endif()

    message(STATUS "Package ${TARGET_TRIPLET}-${BOTAN_BUILD_TYPE} done")
endfunction()

BOTAN_BUILD(rel)
BOTAN_BUILD(dbg)

file(MAKE_DIRECTORY ${CURRENT_PACKAGES_DIR}/tools/botan)

set(cli_exe_name "botan")
if(CMAKE_HOST_WIN32)
    set(cli_exe_name "botan-cli.exe")
endif()
file(RENAME ${CURRENT_PACKAGES_DIR}/bin/${cli_exe_name} ${CURRENT_PACKAGES_DIR}/tools/botan/${cli_exe_name})
file(REMOVE ${CURRENT_PACKAGES_DIR}/debug/bin/${cli_exe_name})

file(RENAME ${CURRENT_PACKAGES_DIR}/include/botan-2/botan ${CURRENT_PACKAGES_DIR}/include/botan)

file(REMOVE_RECURSE
    ${CURRENT_PACKAGES_DIR}/debug/include
    ${CURRENT_PACKAGES_DIR}/debug/share
    ${CURRENT_PACKAGES_DIR}/include/botan-2
    ${CURRENT_PACKAGES_DIR}/share/botan-${BOTAN_VERSION}/manual)

if(VCPKG_LIBRARY_LINKAGE STREQUAL static)
    file(REMOVE_RECURSE
        ${CURRENT_PACKAGES_DIR}/bin
        ${CURRENT_PACKAGES_DIR}/debug/bin)
endif()

vcpkg_copy_pdbs()
vcpkg_copy_tool_dependencies(${CURRENT_PACKAGES_DIR}/tools/botan)

file(RENAME ${CURRENT_PACKAGES_DIR}/share/botan-${BOTAN_VERSION}/ ${CURRENT_PACKAGES_DIR}/share/botan/)
file(RENAME ${CURRENT_PACKAGES_DIR}/share/botan/license.txt ${CURRENT_PACKAGES_DIR}/share/botan/copyright)
