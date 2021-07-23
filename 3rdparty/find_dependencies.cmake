#
# Open3D 3rd party library integration
#
set(Open3D_3RDPARTY_DIR "${CMAKE_CURRENT_LIST_DIR}")

# EXTERNAL_MODULES
# CMake modules we depend on in our public interface. These are modules we
# need to find_package() in our CMake config script, because we will use their
# targets.
set(Open3D_3RDPARTY_EXTERNAL_MODULES)

# PUBLIC_TARGETS
# CMake targets we link against in our public interface. They are
# either locally defined and installed, or imported from an external module
# (see above).
set(Open3D_3RDPARTY_PUBLIC_TARGETS)

# HEADER_TARGETS
# CMake targets we use in our public interface, but as a special case we do not
# need to link against the library. This simplifies dependencies where we merely
# expose declared data types from other libraries in our public headers, so it
# would be overkill to require all library users to link against that dependency.
set(Open3D_3RDPARTY_HEADER_TARGETS)

# PRIVATE_TARGETS
# CMake targets for dependencies which are not exposed in the public API. This
# will probably include HEADER_TARGETS, but also anything else we use internally.
set(Open3D_3RDPARTY_PRIVATE_TARGETS)

find_package(PkgConfig QUIET)

# open3d_build_3rdparty_library(name ...)
#
# Builds a third-party library from source
#
# Valid options:
#    PUBLIC
#        the library belongs to the public interface and must be installed
#    HEADER
#        the library headers belong to the public interface, but the library
#        itself is linked privately
#    INCLUDE_ALL
#        install all files in the include directories. Default is *.h, *.hpp
#    VISIBLE
#        Symbols from this library will be visible for use outside Open3D.
#        Required, for example, if it may throw exceptions that need to be
#        caught in client code.
#    DIRECTORY <dir>
#        the library source directory <dir> is either a subdirectory of
#        3rdparty/ or an absolute directory.
#    INCLUDE_DIRS <dir> [<dir> ...]
#        include headers are in the subdirectories <dir>. Trailing slashes
#        have the same meaning as with install(DIRECTORY). <dir> must be
#        relative to the library source directory.
#        If your include is "#include <x.hpp>" and the path of the file is
#        "path/to/libx/x.hpp" then you need to pass "path/to/libx/"
#        with the trailing "/". If you have "#include <libx/x.hpp>" then you
#        need to pass "path/to/libx".
#    SOURCES <src> [<src> ...]
#        the library sources. Can be omitted for header-only libraries.
#        All sources must be relative to the library source directory.
#    LIBS <target> [<target> ...]
#        extra link dependencies
#    DEPENDS <target> [<target> ...]
#        targets on which <name> depends on and that must be built before.
#
function(open3d_build_3rdparty_library name)
    cmake_parse_arguments(arg "PUBLIC;HEADER;INCLUDE_ALL;VISIBLE" "DIRECTORY" "INCLUDE_DIRS;SOURCES;LIBS;DEPENDS" ${ARGN})
    if(arg_UNPARSED_ARGUMENTS)
        message(STATUS "Unparsed: ${arg_UNPARSED_ARGUMENTS}")
        message(FATAL_ERROR "Invalid syntax: open3d_build_3rdparty_library(${name} ${ARGN})")
    endif()
    get_filename_component(arg_DIRECTORY "${arg_DIRECTORY}" ABSOLUTE BASE_DIR "${Open3D_3RDPARTY_DIR}")
    if(arg_SOURCES)
        add_library(${name} STATIC)
        set_target_properties(${name} PROPERTIES OUTPUT_NAME "${PROJECT_NAME}_${name}")
        open3d_set_global_properties(${name})
    else()
        add_library(${name} INTERFACE)
    endif()
    if(arg_INCLUDE_DIRS)
        set(include_dirs)
        foreach(incl IN LISTS arg_INCLUDE_DIRS)
            list(APPEND include_dirs "${arg_DIRECTORY}/${incl}")
        endforeach()
    else()
        set(include_dirs "${arg_DIRECTORY}/")
    endif()
    if(arg_SOURCES)
        foreach(src IN LISTS arg_SOURCES)
            get_filename_component(abs_src "${src}" ABSOLUTE BASE_DIR "${arg_DIRECTORY}")
            # Mark as generated to skip CMake's file existence checks
            set_source_files_properties(${abs_src} PROPERTIES GENERATED TRUE)
            target_sources(${name} PRIVATE ${abs_src})
        endforeach()
        foreach(incl IN LISTS include_dirs)
            if (incl MATCHES "(.*)/$")
                set(incl_path ${CMAKE_MATCH_1})
            else()
                get_filename_component(incl_path "${incl}" DIRECTORY)
            endif()
            target_include_directories(${name} SYSTEM PUBLIC $<BUILD_INTERFACE:${incl_path}>)
        endforeach()
        # Do not export symbols from 3rd party libraries outside the Open3D DSO.
        if(NOT arg_PUBLIC AND NOT arg_HEADER AND NOT arg_VISIBLE)
            set_target_properties(${name} PROPERTIES
                C_VISIBILITY_PRESET hidden
                CXX_VISIBILITY_PRESET hidden
                CUDA_VISIBILITY_PRESET hidden
                VISIBILITY_INLINES_HIDDEN ON
            )
        endif()
        if(arg_LIBS)
            target_link_libraries(${name} PRIVATE ${arg_LIBS})
        endif()
    else()
        foreach(incl IN LISTS include_dirs)
            if (incl MATCHES "(.*)/$")
                set(incl_path ${CMAKE_MATCH_1})
            else()
                get_filename_component(incl_path "${incl}" DIRECTORY)
            endif()
            target_include_directories(${name} SYSTEM INTERFACE $<BUILD_INTERFACE:${incl_path}>)
        endforeach()
    endif()
    if(NOT BUILD_SHARED_LIBS OR arg_PUBLIC)
        install(TARGETS ${name} EXPORT ${PROJECT_NAME}Targets
            RUNTIME DESTINATION ${Open3D_INSTALL_BIN_DIR}
            ARCHIVE DESTINATION ${Open3D_INSTALL_LIB_DIR}
            LIBRARY DESTINATION ${Open3D_INSTALL_LIB_DIR}
        )
    endif()
    if(arg_PUBLIC OR arg_HEADER)
        foreach(incl IN LISTS include_dirs)
            if(arg_INCLUDE_ALL)
                install(DIRECTORY ${incl}
                    DESTINATION ${Open3D_INSTALL_INCLUDE_DIR}/open3d/3rdparty
                )
            else()
                install(DIRECTORY ${incl}
                    DESTINATION ${Open3D_INSTALL_INCLUDE_DIR}/open3d/3rdparty
                    FILES_MATCHING
                        PATTERN "*.h"
                        PATTERN "*.hpp"
                )
            endif()
            target_include_directories(${name} INTERFACE $<INSTALL_INTERFACE:${Open3D_INSTALL_INCLUDE_DIR}/open3d/3rdparty>)
        endforeach()
    endif()
    if(arg_DEPENDS)
        add_dependencies(${name} ${arg_DEPENDS})
    endif()
    add_library(${PROJECT_NAME}::${name} ALIAS ${name})
endfunction()

# CMake arguments for configuring ExternalProjects. Use the second _hidden
# version by default.
set(ExternalProject_CMAKE_ARGS
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
    -DCMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
    -DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}
    -DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}
    -DCMAKE_CUDA_COMPILER_LAUNCHER=${CMAKE_CUDA_COMPILER_LAUNCHER}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    -DCMAKE_POLICY_DEFAULT_CMP0091:STRING=NEW
    -DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=${CMAKE_MSVC_RUNTIME_LIBRARY}
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    )
# Keep 3rd party symbols hidden from Open3D user code. Do not use if 3rd party
# libraries throw exceptions that escape Open3D.
set(ExternalProject_CMAKE_ARGS_hidden
    ${ExternalProject_CMAKE_ARGS}
    # Apply LANG_VISIBILITY_PRESET to static libraries and archives as well
    -DCMAKE_POLICY_DEFAULT_CMP0063:STRING=NEW
    -DCMAKE_CXX_VISIBILITY_PRESET=hidden
    -DCMAKE_CUDA_VISIBILITY_PRESET=hidden
    -DCMAKE_C_VISIBILITY_PRESET=hidden
    -DCMAKE_VISIBILITY_INLINES_HIDDEN=ON
    )

# open3d_pkg_config_3rdparty_library(name ...)
#
# Creates an interface library for a pkg-config dependency.
#
# The function will set ${name}_FOUND to TRUE or FALSE
# indicating whether or not the library could be found.
#
# Valid options:
#    PUBLIC
#        the library belongs to the public interface and must be installed
#    HEADER
#        the library headers belong to the public interface, but the library
#        itself is linked privately
#    SEARCH_ARGS
#        the arguments passed to pkg_search_module()
#
function(open3d_pkg_config_3rdparty_library name)
    cmake_parse_arguments(arg "PUBLIC;HEADER" "" "SEARCH_ARGS" ${ARGN})
    if(arg_UNPARSED_ARGUMENTS)
        message(STATUS "Unparsed: ${arg_UNPARSED_ARGUMENTS}")
        message(FATAL_ERROR "Invalid syntax: open3d_pkg_config_3rdparty_library(${name} ${ARGN})")
    endif()
    if(PKGCONFIG_FOUND)
        pkg_search_module(pc_${name} ${arg_SEARCH_ARGS})
    endif()
    if(pc_${name}_FOUND)
        message(STATUS "Using installed third-party library ${name} ${${name_uc}_VERSION}")
        add_library(${name} INTERFACE)
        target_include_directories(${name} SYSTEM INTERFACE ${pc_${name}_INCLUDE_DIRS})
        target_link_libraries(${name} INTERFACE ${pc_${name}_LINK_LIBRARIES})
        foreach(flag IN LISTS pc_${name}_CFLAGS_OTHER)
            if(flag MATCHES "-D(.*)")
                target_compile_definitions(${name} INTERFACE ${CMAKE_MATCH_1})
            endif()
        endforeach()
        if(NOT BUILD_SHARED_LIBS OR arg_PUBLIC)
            install(TARGETS ${name} EXPORT ${PROJECT_NAME}Targets)
        endif()
        set(${name}_FOUND TRUE PARENT_SCOPE)
        add_library(${PROJECT_NAME}::${name} ALIAS ${name})
    else()
        message(STATUS "Unable to find installed third-party library ${name}")
        set(${name}_FOUND FALSE PARENT_SCOPE)
    endif()
endfunction()

# open3d_find_package_3rdparty_library(name ...)
#
# Creates an interface library for a find_package dependency.
#
# The function will set ${name}_FOUND to TRUE or FALSE
# indicating whether or not the library could be found.
#
# Valid options:
#    PUBLIC
#        the library belongs to the public interface and must be installed
#    HEADER
#        the library headers belong to the public interface, but the library
#        itself is linked privately
#    REQUIRED
#        finding the package is required
#    QUIET
#        finding the package is quiet
#    PACKAGE <pkg>
#        the name of the queried package <pkg> forwarded to find_package()
#    PACKAGE_VERSION_VAR <pkg_version>
#        the variable <pkg_version> where to find the version of the queried package <pkg> find_package().
#        If not provided, PACKAGE_VERSION_VAR will default to <pkg>_VERSION.
#    TARGETS <target> [<target> ...]
#        the expected targets to be found in <pkg>
#    INCLUDE_DIRS
#        the expected include directory variable names to be found in <pkg>.
#        If <pkg> also defines targets, use them instead and pass them via TARGETS option.
#    LIBRARIES
#        the expected library variable names to be found in <pkg>.
#        If <pkg> also defines targets, use them instead and pass them via TARGETS option.
#
function(open3d_find_package_3rdparty_library name)
    cmake_parse_arguments(arg "PUBLIC;HEADER;REQUIRED;QUIET" "PACKAGE;PACKAGE_VERSION_VAR" "TARGETS;INCLUDE_DIRS;LIBRARIES" ${ARGN})
    if(arg_UNPARSED_ARGUMENTS)
        message(STATUS "Unparsed: ${arg_UNPARSED_ARGUMENTS}")
        message(FATAL_ERROR "Invalid syntax: open3d_find_package_3rdparty_library(${name} ${ARGN})")
    endif()
    if(NOT arg_PACKAGE)
        message(FATAL_ERROR "open3d_find_package_3rdparty_library: Expected value for argument PACKAGE")
    endif()
    if(NOT arg_PACKAGE_VERSION_VAR)
        set(arg_PACKAGE_VERSION_VAR "${arg_PACKAGE}_VERSION")
    endif()
    set(find_package_args "")
    if(arg_REQUIRED)
        list(APPEND find_package_args "REQUIRED")
    endif()
    if(arg_QUIET)
        list(APPEND find_package_args "QUIET")
    endif()
    find_package(${arg_PACKAGE} ${find_package_args})
    if(${arg_PACKAGE}_FOUND)
        message(STATUS "Using installed third-party library ${name} ${${arg_PACKAGE}_VERSION}")
        add_library(${name} INTERFACE)
        if(arg_TARGETS)
            foreach(target IN LISTS arg_TARGETS)
                if (TARGET ${target})
                    target_link_libraries(${name} INTERFACE ${target})
                else()
                    message(WARNING "Skipping undefined target ${target}")
                endif()
            endforeach()
        endif()
        if(arg_INCLUDE_DIRS)
            foreach(incl IN LISTS arg_INCLUDE_DIRS)
                target_include_directories(${name} INTERFACE ${${incl}})
            endforeach()
        endif()
        if(arg_LIBRARIES)
            foreach(lib IN LISTS arg_LIBRARIES)
                target_link_libraries(${name} INTERFACE ${${lib}})
            endforeach()
        endif()
        if(NOT BUILD_SHARED_LIBS OR arg_PUBLIC)
            install(TARGETS ${name} EXPORT ${PROJECT_NAME}Targets)
        endif()
        set(${name}_FOUND TRUE PARENT_SCOPE)
        set(${name}_VERSION ${${arg_PACKAGE_VERSION_VAR}} PARENT_SCOPE)
        add_library(${PROJECT_NAME}::${name} ALIAS ${name})
    else()
        message(STATUS "Unable to find installed third-party library ${name}")
        set(${name}_FOUND FALSE PARENT_SCOPE)
    endif()
endfunction()

# List of linker options for libOpen3D client binaries (eg: pybind) to hide Open3D 3rd
# party dependencies. Only needed with GCC, not AppleClang.
set(OPEN3D_HIDDEN_3RDPARTY_LINK_OPTIONS)

if (CMAKE_CXX_COMPILER_ID STREQUAL AppleClang)
    find_library(LexLIB libl.a)    # test archive in macOS
    if (LexLIB)
        include(CheckCXXSourceCompiles)
        set(CMAKE_REQUIRED_LINK_OPTIONS -load_hidden ${LexLIB})
        check_cxx_source_compiles("int main() {return 0;}" FLAG_load_hidden)
        unset(CMAKE_REQUIRED_LINK_OPTIONS)
    endif()
endif()
if (NOT FLAG_load_hidden)
    set(FLAG_load_hidden 0)
endif()

# open3d_import_3rdparty_library(name ...)
#
# Imports a third-party library that has been built independently in a sub project.
#
# Valid options:
#    PUBLIC
#        the library belongs to the public interface and must be installed
#    HEADER
#        the library headers belong to the public interface and will be
#        installed, but the library is linked privately.
#    INCLUDE_ALL
#        install all files in the include directories. Default is *.h, *.hpp
#    HIDDEN
#         Symbols from this library will not be exported to client code during
#         linking with Open3D. This is the opposite of the VISIBLE option in
#         open3d_build_3rdparty_library.  Prefer hiding symbols during building 3rd
#         party libraries, since this option is not supported by the MSVC linker.
#    INCLUDE_DIRS
#        the temporary location where the library headers have been installed.
#        Trailing slashes have the same meaning as with install(DIRECTORY).
#        If your include is "#include <x.hpp>" and the path of the file is
#        "/path/to/libx/x.hpp" then you need to pass "/path/to/libx/"
#        with the trailing "/". If you have "#include <libx/x.hpp>" then you
#        need to pass "/path/to/libx".
#    LIBRARIES
#        the built library name(s). It is assumed that the library is static.
#        If the library is PUBLIC, it will be renamed to Open3D_${name} at
#        install time to prevent name collisions in the install space.
#    LIB_DIR
#        the temporary location of the library. Defaults to
#        CMAKE_ARCHIVE_OUTPUT_DIRECTORY.
#    DEPENDS <target> [<target> ...]
#        targets on which <name> depends on and that must be built before.
#
function(open3d_import_3rdparty_library name)
    cmake_parse_arguments(arg "PUBLIC;HEADER;INCLUDE_ALL;HIDDEN" "LIB_DIR" "INCLUDE_DIRS;LIBRARIES;DEPENDS" ${ARGN})
    if(arg_UNPARSED_ARGUMENTS)
        message(STATUS "Unparsed: ${arg_UNPARSED_ARGUMENTS}")
        message(FATAL_ERROR "Invalid syntax: open3d_import_3rdparty_library(${name} ${ARGN})")
    endif()
    if(NOT arg_LIB_DIR)
        set(arg_LIB_DIR "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}")
    endif()
    add_library(${name} INTERFACE)
    if(arg_INCLUDE_DIRS)
        foreach(incl IN LISTS arg_INCLUDE_DIRS)
            if (incl MATCHES "(.*)/$")
                set(incl_path ${CMAKE_MATCH_1})
            else()
                get_filename_component(incl_path "${incl}" DIRECTORY)
            endif()
            target_include_directories(${name} SYSTEM INTERFACE $<BUILD_INTERFACE:${incl_path}>)
            if(arg_PUBLIC OR arg_HEADER)
                if(arg_INCLUDE_ALL)
                    install(DIRECTORY ${incl}
                        DESTINATION ${Open3D_INSTALL_INCLUDE_DIR}/open3d/3rdparty
                    )
                else()
                    install(DIRECTORY ${incl}
                        DESTINATION ${Open3D_INSTALL_INCLUDE_DIR}/open3d/3rdparty
                        FILES_MATCHING
                            PATTERN "*.h"
                            PATTERN "*.hpp"
                    )
                endif()
                target_include_directories(${name} INTERFACE $<INSTALL_INTERFACE:${Open3D_INSTALL_INCLUDE_DIR}/open3d/3rdparty>)
            endif()
        endforeach()
    endif()
    if(arg_LIBRARIES)
        list(LENGTH arg_LIBRARIES libcount)
        if(arg_HIDDEN AND NOT arg_PUBLIC AND NOT arg_HEADER)
            set(HIDDEN 1)
        else()
            set(HIDDEN 0)
        endif()
        foreach(arg_LIBRARY IN LISTS arg_LIBRARIES)
            set(library_filename ${CMAKE_STATIC_LIBRARY_PREFIX}${arg_LIBRARY}${CMAKE_STATIC_LIBRARY_SUFFIX})
            if(libcount EQUAL 1)
                set(installed_library_filename ${CMAKE_STATIC_LIBRARY_PREFIX}${PROJECT_NAME}_${name}${CMAKE_STATIC_LIBRARY_SUFFIX})
            else()
                set(installed_library_filename ${CMAKE_STATIC_LIBRARY_PREFIX}${PROJECT_NAME}_${name}_${arg_LIBRARY}${CMAKE_STATIC_LIBRARY_SUFFIX})
            endif()
            # Apple compiler ld
            target_link_libraries(${name} INTERFACE
                "$<BUILD_INTERFACE:$<$<AND:${HIDDEN},${FLAG_load_hidden}>:-load_hidden >${arg_LIB_DIR}/${library_filename}>")
            if(NOT BUILD_SHARED_LIBS OR arg_PUBLIC)
                install(FILES ${arg_LIB_DIR}/${library_filename}
                    DESTINATION ${Open3D_INSTALL_LIB_DIR}
                    RENAME ${installed_library_filename}
                )
                target_link_libraries(${name} INTERFACE $<INSTALL_INTERFACE:$<INSTALL_PREFIX>/${Open3D_INSTALL_LIB_DIR}/${installed_library_filename}>)
            endif()
            if (HIDDEN)
                # GNU compiler ld
                target_link_options(${name} INTERFACE
                    $<$<CXX_COMPILER_ID:GNU>:LINKER:--exclude-libs,${library_filename}>)
                list(APPEND OPEN3D_HIDDEN_3RDPARTY_LINK_OPTIONS $<$<CXX_COMPILER_ID:GNU>:LINKER:--exclude-libs,${library_filename}>)
                set(OPEN3D_HIDDEN_3RDPARTY_LINK_OPTIONS
                    ${OPEN3D_HIDDEN_3RDPARTY_LINK_OPTIONS} PARENT_SCOPE)
            endif()
        endforeach()
    endif()
    if(NOT BUILD_SHARED_LIBS OR arg_PUBLIC)
        install(TARGETS ${name} EXPORT ${PROJECT_NAME}Targets)
    endif()
    if(arg_DEPENDS)
        add_dependencies(${name} ${arg_DEPENDS})
    endif()
    add_library(${PROJECT_NAME}::${name} ALIAS ${name})
endfunction()

include(ProcessorCount)
ProcessorCount(NPROC)

# CUDAToolkit
if(BUILD_CUDA_MODULE)
    find_package(CUDAToolkit REQUIRED)
    list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "CUDAToolkit")
endif()

# Threads
set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
set(THREADS_PREFER_PTHREAD_FLAG TRUE) # -pthread instead of -lpthread
open3d_find_package_3rdparty_library(3rdparty_threads
    REQUIRED
    PACKAGE Threads
    TARGETS Threads::Threads
)
list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "Threads")

# Assimp
include(${Open3D_3RDPARTY_DIR}/assimp/assimp.cmake)
open3d_import_3rdparty_library(3rdparty_assimp
    INCLUDE_DIRS ${ASSIMP_INCLUDE_DIR}
    LIB_DIR      ${ASSIMP_LIB_DIR}
    LIBRARIES    ${ASSIMP_LIBRARIES}
    DEPENDS      ext_assimp
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_assimp)

# OpenMP
if(WITH_OPENMP)
    open3d_find_package_3rdparty_library(3rdparty_openmp
        PACKAGE OpenMP
        PACKAGE_VERSION_VAR OpenMP_CXX_VERSION
        TARGETS OpenMP::OpenMP_CXX
    )
    if(3rdparty_openmp_FOUND)
        message(STATUS "Building with OpenMP")
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "OpenMP")
        endif()
        list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_openmp)
    endif()
endif()

# X11
if(UNIX AND NOT APPLE)
    open3d_find_package_3rdparty_library(3rdparty_x11
        QUIET
        PACKAGE X11
        TARGETS X11::X11
    )
    if(3rdparty_x11_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "X11")
        endif()
    endif()
endif()

# CUB (already included in CUDA 11.0+)
if(BUILD_CUDA_MODULE AND CUDAToolkit_VERSION VERSION_LESS "11.0")
    include(${Open3D_3RDPARTY_DIR}/cub/cub.cmake)
    open3d_import_3rdparty_library(3rdparty_cub
        INCLUDE_DIRS ${CUB_INCLUDE_DIRS}
        DEPENDS      ext_cub
    )
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_cub)
endif()

# cutlass
if(BUILD_CUDA_MODULE)
    include(${Open3D_3RDPARTY_DIR}/cutlass/cutlass.cmake)
    open3d_import_3rdparty_library(3rdparty_cutlass
        INCLUDE_DIRS ${CUTLASS_INCLUDE_DIRS}
        DEPENDS      ext_cutlass
    )
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_cutlass)
endif()

# Dirent
if(WIN32)
    open3d_build_3rdparty_library(3rdparty_dirent DIRECTORY dirent)
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_dirent)
endif()

# Eigen3
if(USE_SYSTEM_EIGEN3)
    open3d_find_package_3rdparty_library(3rdparty_eigen3
        PUBLIC
        PACKAGE Eigen3
        TARGETS Eigen3::Eigen
    )
    if(3rdparty_eigen3_FOUND)
        # Eigen3 is a publicly visible dependency, so add it to the list of
        # modules we need to find in the Open3D config script.
        list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "Eigen3")
    else()
        set(USE_SYSTEM_EIGEN3 OFF)
    endif()
endif()
if(NOT USE_SYSTEM_EIGEN3)
    include(${Open3D_3RDPARTY_DIR}/eigen/eigen.cmake)
    open3d_import_3rdparty_library(3rdparty_eigen3
        PUBLIC
        INCLUDE_DIRS ${EIGEN_INCLUDE_DIRS}
        INCLUDE_ALL
        DEPENDS      ext_eigen
    )
endif()
list(APPEND Open3D_3RDPARTY_PUBLIC_TARGETS Open3D::3rdparty_eigen3)

# Nanoflann
include(${Open3D_3RDPARTY_DIR}/nanoflann/nanoflann.cmake)
open3d_import_3rdparty_library(3rdparty_nanoflann
    INCLUDE_DIRS ${NANOFLANN_INCLUDE_DIRS}
    DEPENDS      ext_nanoflann
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_nanoflann)

# GLEW
if(USE_SYSTEM_GLEW)
    open3d_find_package_3rdparty_library(3rdparty_glew
        HEADER
        PACKAGE GLEW
        TARGETS GLEW::GLEW
    )
    if(3rdparty_glew_FOUND)
        list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "GLEW")
    else()
        open3d_pkg_config_3rdparty_library(3rdparty_glew
            HEADER
            SEARCH_ARGS glew
        )
        if(NOT 3rdparty_glew_FOUND)
            set(USE_SYSTEM_GLEW OFF)
        endif()
    endif()
endif()
if(NOT USE_SYSTEM_GLEW)
    open3d_build_3rdparty_library(3rdparty_glew DIRECTORY glew
        HEADER
        SOURCES
            src/glew.c
        INCLUDE_DIRS
            include/
    )
    if(ENABLE_HEADLESS_RENDERING)
        target_compile_definitions(3rdparty_glew PUBLIC GLEW_OSMESA)
    endif()
    if(WIN32)
        target_compile_definitions(3rdparty_glew PUBLIC GLEW_STATIC)
    endif()
endif()
list(APPEND Open3D_3RDPARTY_HEADER_TARGETS Open3D::3rdparty_glew)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_glew)

# GLFW
if(USE_SYSTEM_GLFW)
    open3d_find_package_3rdparty_library(3rdparty_glfw
        HEADER
        PACKAGE glfw3
        TARGETS glfw
    )
    if(3rdparty_glfw_FOUND)
        list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "glfw3")
    else()
        open3d_pkg_config_3rdparty_library(3rdparty_glfw
            HEADER
            SEARCH_ARGS glfw3
        )
        if(NOT 3rdparty_glfw_FOUND)
            set(USE_SYSTEM_GLFW OFF)
        endif()
    endif()
endif()
if(NOT USE_SYSTEM_GLFW)
    message(STATUS "Building library 3rdparty_glfw from source")
    add_subdirectory(${Open3D_3RDPARTY_DIR}/GLFW)
    open3d_import_3rdparty_library(3rdparty_glfw
        HEADER
        INCLUDE_DIRS ${Open3D_3RDPARTY_DIR}/GLFW/include/
        LIBRARIES    glfw3
        DEPENDS      glfw
    )
    target_link_libraries(3rdparty_glfw INTERFACE Open3D::3rdparty_threads)
    if(UNIX AND NOT APPLE)
        find_library(RT_LIBRARY rt)
        if(RT_LIBRARY)
            target_link_libraries(3rdparty_glfw INTERFACE ${RT_LIBRARY})
        endif()
        find_library(MATH_LIBRARY m)
        if(MATH_LIBRARY)
            target_link_libraries(3rdparty_glfw INTERFACE ${MATH_LIBRARY})
        endif()
        if(CMAKE_DL_LIBS)
            target_link_libraries(3rdparty_glfw INTERFACE ${CMAKE_DL_LIBS})
        endif()
    endif()
    if(APPLE)
        find_library(COCOA_FRAMEWORK Cocoa)
        find_library(IOKIT_FRAMEWORK IOKit)
        find_library(CORE_FOUNDATION_FRAMEWORK CoreFoundation)
        find_library(CORE_VIDEO_FRAMEWORK CoreVideo)
        target_link_libraries(3rdparty_glfw INTERFACE ${COCOA_FRAMEWORK} ${IOKIT_FRAMEWORK} ${CORE_FOUNDATION_FRAMEWORK} ${CORE_VIDEO_FRAMEWORK})
    endif()
    if(WIN32)
        target_link_libraries(3rdparty_glfw INTERFACE gdi32)
    endif()
endif()
if(TARGET Open3D::3rdparty_x11)
    target_link_libraries(3rdparty_glfw INTERFACE Open3D::3rdparty_x11)
endif()
list(APPEND Open3D_3RDPARTY_HEADER_TARGETS Open3D::3rdparty_glfw)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_glfw)

# TurboJPEG
if(USE_SYSTEM_JPEG AND BUILD_AZURE_KINECT)
    open3d_pkg_config_3rdparty_library(3rdparty_turbojpeg
        SEARCH_ARGS turbojpeg
    )
    if(3rdparty_turbojpeg_FOUND)
        message(STATUS "Using installed third-party library turbojpeg")
    else()
        message(STATUS "Unable to find installed third-party library turbojpeg")
        message(STATUS "Azure Kinect driver needs TurboJPEG API")
        set(USE_SYSTEM_JPEG OFF)
    endif()
endif()

# JPEG
if(USE_SYSTEM_JPEG)
    open3d_find_package_3rdparty_library(3rdparty_jpeg
        PACKAGE JPEG
        TARGETS JPEG::JPEG
    )
    if(3rdparty_jpeg_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "JPEG")
        endif()
        if(TARGET Open3D::3rdparty_turbojpeg)
            list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_turbojpeg)
        endif()
    else()
        set(USE_SYSTEM_JPEG OFF)
    endif()
endif()
if(NOT USE_SYSTEM_JPEG)
    message(STATUS "Building third-party library JPEG from source")
    include(${Open3D_3RDPARTY_DIR}/libjpeg-turbo/libjpeg-turbo.cmake)
    open3d_import_3rdparty_library(3rdparty_jpeg
        INCLUDE_DIRS ${JPEG_TURBO_INCLUDE_DIRS}
        LIB_DIR      ${JPEG_TURBO_LIB_DIR}
        LIBRARIES    ${JPEG_TURBO_LIBRARIES}
        DEPENDS      ext_turbojpeg
    )
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_jpeg)

# jsoncpp: always compile from source to avoid ABI issues.
include(${Open3D_3RDPARTY_DIR}/jsoncpp/jsoncpp.cmake)
open3d_import_3rdparty_library(3rdparty_jsoncpp
    INCLUDE_DIRS ${JSONCPP_INCLUDE_DIRS}
    LIB_DIR      ${JSONCPP_LIB_DIR}
    LIBRARIES    ${JSONCPP_LIBRARIES}
    DEPENDS      ext_jsoncpp
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_jsoncpp)

# liblzf
if(USE_SYSTEM_LIBLZF)
    open3d_find_package_3rdparty_library(3rdparty_liblzf
        PACKAGE liblzf
        TARGETS liblzf::liblzf
    )
    if(3rdparty_liblzf_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "JPEG")
        endif()
    else()
        set(USE_SYSTEM_LIBLZF OFF)
    endif()
endif()
if(NOT USE_SYSTEM_LIBLZF)
    open3d_build_3rdparty_library(3rdparty_liblzf DIRECTORY liblzf
        SOURCES
            liblzf/lzf_c.c
            liblzf/lzf_d.c
    )
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_liblzf)

# tritriintersect
open3d_build_3rdparty_library(3rdparty_tritriintersect DIRECTORY tomasakeninemoeller
    INCLUDE_DIRS include/
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_tritriintersect)

# librealsense SDK
if (BUILD_LIBREALSENSE)
    if(USE_SYSTEM_LIBREALSENSE AND NOT GLIBCXX_USE_CXX11_ABI)
        # Turn off USE_SYSTEM_LIBREALSENSE.
        # Because it is affected by libraries built with different CXX ABIs.
        # See details: https://github.com/intel-isl/Open3D/pull/2876
        message(STATUS "Set USE_SYSTEM_LIBREALSENSE=OFF, because GLIBCXX_USE_CXX11_ABI is OFF.")
        set(USE_SYSTEM_LIBREALSENSE OFF)
    endif()
    if(USE_SYSTEM_LIBREALSENSE)
        open3d_find_package_3rdparty_library(3rdparty_librealsense
            PACKAGE realsense2
            TARGETS realsense2::realsense2
        )
        if(3rdparty_librealsense_FOUND)
            if(NOT BUILD_SHARED_LIBS)
                list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "realsense2")
            endif()
        else()
            set(USE_SYSTEM_LIBREALSENSE OFF)
        endif()
    endif()
    if(NOT USE_SYSTEM_LIBREALSENSE)
        include(${Open3D_3RDPARTY_DIR}/librealsense/librealsense.cmake)
        open3d_import_3rdparty_library(3rdparty_librealsense
            INCLUDE_DIRS ${LIBREALSENSE_INCLUDE_DIR}
            LIBRARIES    ${LIBREALSENSE_LIBRARIES}
            LIB_DIR      ${LIBREALSENSE_LIB_DIR}
            DEPENDS      ext_librealsense
        )
        if (UNIX AND NOT APPLE)    # Ubuntu dependency: libudev-dev
            find_library(UDEV_LIBRARY udev REQUIRED
                DOC "Library provided by the deb package libudev-dev")
            target_link_libraries(3rdparty_librealsense INTERFACE ${UDEV_LIBRARY})
        endif()
    endif()
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_librealsense)
endif()

# PNG
if(USE_SYSTEM_PNG)
    # ZLIB::ZLIB is automatically included by the PNG package.
    open3d_find_package_3rdparty_library(3rdparty_png
        PACKAGE PNG
        PACKAGE_VERSION_VAR PNG_VERSION_STRING
        TARGETS PNG::PNG
    )
    if(3rdparty_png_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "PNG")
        endif()
    else()
        set(USE_SYSTEM_PNG OFF)
    endif()
endif()
if(NOT USE_SYSTEM_PNG)
    include(${Open3D_3RDPARTY_DIR}/zlib/zlib.cmake)
    open3d_import_3rdparty_library(3rdparty_zlib
        HIDDEN
        INCLUDE_DIRS ${ZLIB_INCLUDE_DIRS}
        LIB_DIR      ${ZLIB_LIB_DIR}
        LIBRARIES    ${ZLIB_LIBRARIES}
        DEPENDS      ext_zlib
    )

    include(${Open3D_3RDPARTY_DIR}/libpng/libpng.cmake)
    open3d_import_3rdparty_library(3rdparty_png
        INCLUDE_DIRS ${LIBPNG_INCLUDE_DIRS}
        LIB_DIR      ${LIBPNG_LIB_DIR}
        LIBRARIES    ${LIBPNG_LIBRARIES}
        DEPENDS      ext_libpng
    )
    add_dependencies(ext_libpng ext_zlib)
    target_link_libraries(3rdparty_png INTERFACE Open3D::3rdparty_zlib)
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_png)

# rply
open3d_build_3rdparty_library(3rdparty_rply DIRECTORY rply
    SOURCES
        rply/rply.c
    INCLUDE_DIRS
        rply/
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_rply)

# tinyfiledialogs
open3d_build_3rdparty_library(3rdparty_tinyfiledialogs DIRECTORY tinyfiledialogs
    SOURCES
        include/tinyfiledialogs/tinyfiledialogs.c
    INCLUDE_DIRS
        include/
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_tinyfiledialogs)

# tinygltf
if(USE_SYSTEM_TINYGLTF)
    open3d_find_package_3rdparty_library(3rdparty_tinygltf
        PACKAGE TinyGLTF
        TARGETS TinyGLTF::TinyGLTF
    )
    if(3rdparty_tinygltf_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "TinyGLTF")
        endif()
    else()
        set(USE_SYSTEM_TINYGLTF OFF)
    endif()
endif()
if(NOT USE_SYSTEM_TINYGLTF)
    include(${Open3D_3RDPARTY_DIR}/tinygltf/tinygltf.cmake)
    open3d_import_3rdparty_library(3rdparty_tinygltf
        INCLUDE_DIRS ${TINYGLTF_INCLUDE_DIRS}
        DEPENDS      ext_tinygltf
    )
    target_compile_definitions(3rdparty_tinygltf INTERFACE TINYGLTF_IMPLEMENTATION STB_IMAGE_IMPLEMENTATION STB_IMAGE_WRITE_IMPLEMENTATION)
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_tinygltf)

# tinyobjloader
if(USE_SYSTEM_TINYOBJLOADER)
    open3d_find_package_3rdparty_library(3rdparty_tinyobjloader
        PACKAGE tinyobjloader
        TARGETS tinyobjloader::tinyobjloader
    )
    if(3rdparty_tinyobjloader_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "tinyobjloader")
        endif()
    else()
        set(USE_SYSTEM_TINYOBJLOADER OFF)
    endif()
endif()
if(NOT USE_SYSTEM_TINYOBJLOADER)
    include(${Open3D_3RDPARTY_DIR}/tinyobjloader/tinyobjloader.cmake)
    open3d_import_3rdparty_library(3rdparty_tinyobjloader
        INCLUDE_DIRS ${TINYOBJLOADER_INCLUDE_DIRS}
        DEPENDS      ext_tinyobjloader
    )
    target_compile_definitions(3rdparty_tinyobjloader INTERFACE TINYOBJLOADER_IMPLEMENTATION)
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_tinyobjloader)

# Qhullcpp
if(USE_SYSTEM_QHULLCPP)
    open3d_find_package_3rdparty_library(3rdparty_qhullcpp
        PACKAGE Qhull
        TARGETS Qhull::qhullcpp
    )
    if(3rdparty_qhullcpp_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "Qhull")
        endif()
    else()
        set(USE_SYSTEM_QHULLCPP OFF)
    endif()
endif()
if(NOT USE_SYSTEM_QHULLCPP)
    include(${Open3D_3RDPARTY_DIR}/qhull/qhull.cmake)
    open3d_build_3rdparty_library(3rdparty_qhull_r DIRECTORY ${QHULL_SOURCE_DIR}
        SOURCES
            src/libqhull_r/global_r.c
            src/libqhull_r/stat_r.c
            src/libqhull_r/geom2_r.c
            src/libqhull_r/poly2_r.c
            src/libqhull_r/merge_r.c
            src/libqhull_r/libqhull_r.c
            src/libqhull_r/geom_r.c
            src/libqhull_r/poly_r.c
            src/libqhull_r/qset_r.c
            src/libqhull_r/mem_r.c
            src/libqhull_r/random_r.c
            src/libqhull_r/usermem_r.c
            src/libqhull_r/userprintf_r.c
            src/libqhull_r/io_r.c
            src/libqhull_r/user_r.c
            src/libqhull_r/rboxlib_r.c
            src/libqhull_r/userprintf_rbox_r.c
        INCLUDE_DIRS
            src/
        DEPENDS
            ext_qhull
    )
    open3d_build_3rdparty_library(3rdparty_qhullcpp DIRECTORY ${QHULL_SOURCE_DIR}
        SOURCES
            src/libqhullcpp/Coordinates.cpp
            src/libqhullcpp/PointCoordinates.cpp
            src/libqhullcpp/Qhull.cpp
            src/libqhullcpp/QhullFacet.cpp
            src/libqhullcpp/QhullFacetList.cpp
            src/libqhullcpp/QhullFacetSet.cpp
            src/libqhullcpp/QhullHyperplane.cpp
            src/libqhullcpp/QhullPoint.cpp
            src/libqhullcpp/QhullPointSet.cpp
            src/libqhullcpp/QhullPoints.cpp
            src/libqhullcpp/QhullQh.cpp
            src/libqhullcpp/QhullRidge.cpp
            src/libqhullcpp/QhullSet.cpp
            src/libqhullcpp/QhullStat.cpp
            src/libqhullcpp/QhullVertex.cpp
            src/libqhullcpp/QhullVertexSet.cpp
            src/libqhullcpp/RboxPoints.cpp
            src/libqhullcpp/RoadError.cpp
            src/libqhullcpp/RoadLogEvent.cpp
        INCLUDE_DIRS
            src/
        DEPENDS
            ext_qhull
    )
    target_link_libraries(3rdparty_qhullcpp PRIVATE 3rdparty_qhull_r)
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_qhullcpp)

# fmt
if(USE_SYSTEM_FMT)
    open3d_find_package_3rdparty_library(3rdparty_fmt
        PUBLIC
        PACKAGE fmt
        TARGETS fmt::fmt-header-only fmt::fmt
    )
    if(3rdparty_fmt_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "fmt")
        endif()
    else()
        set(USE_SYSTEM_FMT OFF)
    endif()
endif()
if(NOT USE_SYSTEM_FMT)
    # We set the FMT_HEADER_ONLY macro, so no need to actually compile the source
    include(${Open3D_3RDPARTY_DIR}/fmt/fmt.cmake)
    open3d_import_3rdparty_library(3rdparty_fmt
        PUBLIC
        INCLUDE_DIRS ${FMT_INCLUDE_DIRS}
        DEPENDS      ext_fmt
    )
    target_compile_definitions(3rdparty_fmt INTERFACE FMT_HEADER_ONLY=1)
endif()
list(APPEND Open3D_3RDPARTY_PUBLIC_TARGETS Open3D::3rdparty_fmt)

# Pybind11
if (BUILD_PYTHON_MODULE)
    if(USE_SYSTEM_PYBIND11)
        find_package(pybind11)
    endif()
    if (NOT USE_SYSTEM_PYBIND11 OR NOT TARGET pybind11::module)
        set(USE_SYSTEM_PYBIND11 OFF)
        include(${Open3D_3RDPARTY_DIR}/pybind11/pybind11.cmake)
        # pybind11 will automatically become available.
    endif()
endif()

# Azure Kinect
set(BUILD_AZURE_KINECT_COMMENT "//") # Set include header files in Open3D.h
if (BUILD_AZURE_KINECT)
    include(${Open3D_3RDPARTY_DIR}/azure_kinect/azure_kinect.cmake)
    open3d_import_3rdparty_library(3rdparty_k4a
        INCLUDE_DIRS ${K4A_INCLUDE_DIR}
        DEPENDS      ext_k4a
    )
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_k4a)
endif()

# PoissonRecon
include(${Open3D_3RDPARTY_DIR}/PoissonRecon/PoissonRecon.cmake)
open3d_import_3rdparty_library(3rdparty_poisson
    INCLUDE_DIRS ${POISSON_INCLUDE_DIRS}
    DEPENDS      ext_poisson
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_poisson)

# Googletest
if (BUILD_UNIT_TESTS)
    if(USE_SYSTEM_GOOGLETEST)
        find_path(gtest_INCLUDE_DIRS gtest/gtest.h)
        find_library(gtest_LIBRARY gtest)
        find_path(gmock_INCLUDE_DIRS gmock/gmock.h)
        find_library(gmock_LIBRARY gmock)
        if(gtest_INCLUDE_DIRS AND gtest_LIBRARY AND gmock_INCLUDE_DIRS AND gmock_LIBRARY)
            message(STATUS "Using installed googletest")
            add_library(3rdparty_googletest INTERFACE)
            target_include_directories(3rdparty_googletest INTERFACE ${gtest_INCLUDE_DIRS} ${gmock_INCLUDE_DIRS})
            target_link_libraries(3rdparty_googletest INTERFACE ${gtest_LIBRARY} ${gmock_LIBRARY})
            add_library(Open3D::3rdparty_googletest ALIAS 3rdparty_googletest)
        else()
            message(STATUS "Unable to find installed googletest")
            set(USE_SYSTEM_GOOGLETEST OFF)
        endif()
    endif()
    if(NOT USE_SYSTEM_GOOGLETEST)
        include(${Open3D_3RDPARTY_DIR}/googletest/googletest.cmake)
        open3d_build_3rdparty_library(3rdparty_googletest DIRECTORY ${GOOGLETEST_SOURCE_DIR}
            SOURCES
                googletest/src/gtest-all.cc
                googlemock/src/gmock-all.cc
            INCLUDE_DIRS
                googletest/include/
                googletest/
                googlemock/include/
                googlemock/
            DEPENDS
                ext_googletest
        )
    endif()
endif()

# Google benchmark
if (BUILD_BENCHMARKS)
    include(${Open3D_3RDPARTY_DIR}/benchmark/benchmark.cmake)
    # benchmark and benchmark_main will automatically become available.
endif()

# Headless rendering
if (ENABLE_HEADLESS_RENDERING)
    open3d_find_package_3rdparty_library(3rdparty_opengl
        REQUIRED
        PACKAGE OSMesa
        INCLUDE_DIRS OSMESA_INCLUDE_DIR
        LIBRARIES OSMESA_LIBRARY
    )
else()
    open3d_find_package_3rdparty_library(3rdparty_opengl
        PACKAGE OpenGL
        TARGETS OpenGL::GL
    )
    if(3rdparty_opengl_FOUND)
        if(NOT BUILD_SHARED_LIBS)
            list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "OpenGL")
        endif()
    endif()
endif()
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_opengl)

# imgui
if(BUILD_GUI)
    if(USE_SYSTEM_IMGUI)
        open3d_find_package_3rdparty_library(3rdparty_imgui
            PACKAGE ImGui
            TARGETS ImGui::ImGui
        )
        if(3rdparty_imgui_FOUND)
            if(NOT BUILD_SHARED_LIBS)
                list(APPEND Open3D_3RDPARTY_EXTERNAL_MODULES "ImGui")
            endif()
        else()
            set(USE_SYSTEM_IMGUI OFF)
        endif()
    endif()
    if(NOT USE_SYSTEM_IMGUI)
        include(${Open3D_3RDPARTY_DIR}/imgui/imgui.cmake)
        open3d_build_3rdparty_library(3rdparty_imgui DIRECTORY ${IMGUI_SOURCE_DIR}
            SOURCES
                imgui_demo.cpp
                imgui_draw.cpp
                imgui_widgets.cpp
                imgui.cpp
            DEPENDS
                ext_imgui
        )
    endif()
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_imgui)
endif()

# Filament
if(BUILD_GUI)
    set(FILAMENT_RUNTIME_VER "")
    if(BUILD_FILAMENT_FROM_SOURCE)
        message(STATUS "Building third-party library Filament from source")
        if(MSVC OR (CMAKE_C_COMPILER_ID MATCHES ".*Clang" AND
            CMAKE_CXX_COMPILER_ID MATCHES ".*Clang"
            AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 7))
            set(FILAMENT_C_COMPILER "${CMAKE_C_COMPILER}")
            set(FILAMENT_CXX_COMPILER "${CMAKE_CXX_COMPILER}")
        else()
            message(STATUS "Filament can only be built with Clang >= 7")
            # First, check default version, because the user may have configured
            # a particular version as default for a reason.
            find_program(CLANG_DEFAULT_CC NAMES clang)
            find_program(CLANG_DEFAULT_CXX NAMES clang++)
            if(CLANG_DEFAULT_CC AND CLANG_DEFAULT_CXX)
                execute_process(COMMAND ${CLANG_DEFAULT_CXX} --version OUTPUT_VARIABLE clang_version)
                if(clang_version MATCHES "clang version ([0-9]+)")
                    if (CMAKE_MATCH_1 GREATER_EQUAL 7)
                        message(STATUS "Using ${CLANG_DEFAULT_CXX} to build Filament")
                        set(FILAMENT_C_COMPILER "${CLANG_DEFAULT_CC}")
                        set(FILAMENT_CXX_COMPILER "${CLANG_DEFAULT_CXX}")
                    endif()
                endif()
            endif()
            # If the default version is not sufficient, look for some specific versions
            if(NOT FILAMENT_C_COMPILER OR NOT FILAMENT_CXX_COMPILER)
                find_program(CLANG_VERSIONED_CC NAMES clang-12 clang-11 clang-10 clang-9 clang-8 clang-7)
                find_program(CLANG_VERSIONED_CXX NAMES clang++-12 clang++11 clang++-10 clang++-9 clang++-8 clang++-7)
                if (CLANG_VERSIONED_CC AND CLANG_VERSIONED_CXX)
                    set(FILAMENT_C_COMPILER "${CLANG_VERSIONED_CC}")
                    set(FILAMENT_CXX_COMPILER "${CLANG_VERSIONED_CXX}")
                    message(STATUS "Using ${CLANG_VERSIONED_CXX} to build Filament")
                else()
                    message(FATAL_ERROR "Need Clang >= 7 to compile Filament from source")
                endif()
            endif()
        endif()
        if (UNIX AND NOT APPLE)
            # Find corresponding libc++ and libc++abi libraries. On Ubuntu, clang
            # libraries are located at /usr/lib/llvm-{version}/lib, and the default
            # version will have a sybolic link at /usr/lib/x86_64-linux-gnu/ or
            # /usr/lib/aarch64-linux-gnu.
            # For aarch64, the symbolic link path may not work for CMake's
            # find_library. Therefore, when compiling Filament from source, we
            # explicitly find the corresponidng path based on the clang version.
            execute_process(COMMAND ${FILAMENT_CXX_COMPILER} --version OUTPUT_VARIABLE clang_version)
            if(clang_version MATCHES "clang version ([0-9]+)")
                set(CLANG_LIBDIR "/usr/lib/llvm-${CMAKE_MATCH_1}/lib")
            endif()
        endif()
        include(${Open3D_3RDPARTY_DIR}/filament/filament_build.cmake)
    else()
        message(STATUS "Using prebuilt third-party library Filament")
        include(${Open3D_3RDPARTY_DIR}/filament/filament_download.cmake)
        # Set lib directory for filament v1.9.9 on Windows.
        # Assume newer version if FILAMENT_PRECOMPILED_ROOT is set.
        if (WIN32 AND NOT FILAMENT_PRECOMPILED_ROOT)
            if (STATIC_WINDOWS_RUNTIME)
                set(FILAMENT_RUNTIME_VER "x86_64/mt$<$<CONFIG:DEBUG>:d>")
            else()
                set(FILAMENT_RUNTIME_VER "x86_64/md$<$<CONFIG:DEBUG>:d>")
            endif()
        endif()
    endif()
    if (APPLE)
        set(FILAMENT_RUNTIME_VER x86_64)
    endif()
    open3d_import_3rdparty_library(3rdparty_filament
        HEADER
        INCLUDE_DIRS ${FILAMENT_ROOT}/include/
        LIB_DIR ${FILAMENT_ROOT}/lib/${FILAMENT_RUNTIME_VER}
        LIBRARIES ${filament_LIBRARIES}
        DEPENDS ext_filament
    )
    set(FILAMENT_MATC "${FILAMENT_ROOT}/bin/matc")
    target_link_libraries(3rdparty_filament INTERFACE Open3D::3rdparty_threads ${CMAKE_DL_LIBS})
    if(UNIX AND NOT APPLE)
        # Find CLANG_LIBDIR if it is not defined. Mutiple paths will be searched.
        if (NOT CLANG_LIBDIR)
            find_library(CPPABI_LIBRARY c++abi PATH_SUFFIXES
                         llvm-12/lib llvm-11/lib llvm-10/lib llvm-9/lib llvm-8/lib llvm-7/lib
                         REQUIRED)
            get_filename_component(CLANG_LIBDIR ${CPPABI_LIBRARY} DIRECTORY)
        endif()
        # Find clang libraries at the exact path ${CLANG_LIBDIR}.
        find_library(CPP_LIBRARY    c++    PATHS ${CLANG_LIBDIR} REQUIRED NO_DEFAULT_PATH)
        find_library(CPPABI_LIBRARY c++abi PATHS ${CLANG_LIBDIR} REQUIRED NO_DEFAULT_PATH)
        # Ensure that libstdc++ gets linked first
        target_link_libraries(3rdparty_filament INTERFACE -lstdc++
                              ${CPP_LIBRARY} ${CPPABI_LIBRARY})
        message(STATUS "CLANG_LIBDIR: ${CLANG_LIBDIR}")
        message(STATUS "CPP_LIBRARY: ${CPP_LIBRARY}")
        message(STATUS "CPPABI_LIBRARY: ${CPPABI_LIBRARY}")
    endif()
    if (APPLE)
        find_library(CORE_VIDEO CoreVideo)
        find_library(QUARTZ_CORE QuartzCore)
        find_library(OPENGL_LIBRARY OpenGL)
        find_library(METAL_LIBRARY Metal)
        find_library(APPKIT_LIBRARY AppKit)
        target_link_libraries(3rdparty_filament INTERFACE ${CORE_VIDEO} ${QUARTZ_CORE} ${OPENGL_LIBRARY} ${METAL_LIBRARY} ${APPKIT_LIBRARY})
        target_link_options(3rdparty_filament INTERFACE "-fobjc-link-runtime")
    endif()
    list(APPEND Open3D_3RDPARTY_HEADER_TARGETS Open3D::3rdparty_filament)
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_filament)
endif()

# RPC interface
# zeromq
include(${Open3D_3RDPARTY_DIR}/zeromq/zeromq_build.cmake)
open3d_import_3rdparty_library(3rdparty_zeromq
    HIDDEN
    INCLUDE_DIRS ${ZEROMQ_INCLUDE_DIRS}
    LIB_DIR      ${ZEROMQ_LIB_DIR}
    LIBRARIES    ${ZEROMQ_LIBRARIES}
    DEPENDS      ext_zeromq ext_cppzmq
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_zeromq)
if(DEFINED ZEROMQ_ADDITIONAL_LIBS)
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS ${ZEROMQ_ADDITIONAL_LIBS})
endif()

# msgpack
include(${Open3D_3RDPARTY_DIR}/msgpack/msgpack_build.cmake)
open3d_import_3rdparty_library(3rdparty_msgpack
    INCLUDE_DIRS ${MSGPACK_INCLUDE_DIRS}
    DEPENDS      ext_msgpack-c
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_msgpack)

# TBB
include(${Open3D_3RDPARTY_DIR}/mkl/tbb.cmake)
open3d_import_3rdparty_library(3rdparty_tbb
    INCLUDE_DIRS ${STATIC_TBB_INCLUDE_DIR}
    LIB_DIR      ${STATIC_TBB_LIB_DIR}
    LIBRARIES    ${STATIC_TBB_LIBRARIES}
    DEPENDS      ext_tbb
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_tbb)

# parallelstl
include(${Open3D_3RDPARTY_DIR}/parallelstl/parallelstl.cmake)
open3d_import_3rdparty_library(3rdparty_parallelstl
    PUBLIC
    INCLUDE_DIRS ${PARALLELSTL_INCLUDE_DIRS}
    INCLUDE_ALL
    DEPENDS      ext_parallelstl
)
list(APPEND Open3D_3RDPARTY_PUBLIC_TARGETS Open3D::3rdparty_parallelstl)

if(USE_BLAS)
    # Try to locate system BLAS/LAPACK
    find_package(BLAS)
    find_package(LAPACK)
    find_package(LAPACKE)
    if(BLAS_FOUND AND LAPACK_FOUND AND LAPACKE_FOUND)
        message(STATUS "Using system BLAS/LAPACK")
        list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS "${BLAS_LIBRARIES}")
        list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS "${LAPACK_LIBRARIES}")
        list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS "${LAPACKE_LIBRARIES}")
        if(BUILD_CUDA_MODULE)
            list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS CUDA::cublas_static CUDA::cublasLt_static CUDA::cusolver_static)
        endif()
    else()
        # Compile OpenBLAS/Lapack from source. Install gfortran on Ubuntu first.
        message(STATUS "Building OpenBLAS with LAPACK from source")
        set(BLAS_BUILD_FROM_SOURCE ON)

        include(${Open3D_3RDPARTY_DIR}/openblas/openblas.cmake)
        open3d_import_3rdparty_library(3rdparty_openblas
            HIDDEN
            INCLUDE_DIRS ${OPENBLAS_INCLUDE_DIR}
            LIB_DIR      ${OPENBLAS_LIB_DIR}
            LIBRARIES    ${OPENBLAS_LIBRARIES}
            DEPENDS      ext_openblas
        )
        target_link_libraries(3rdparty_openblas INTERFACE Threads::Threads gfortran)
        if(BUILD_CUDA_MODULE)
            target_link_libraries(3rdparty_openblas INTERFACE CUDA::cublas_static CUDA::cublasLt_static CUDA::cusolver_static)
        endif()
        list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_openblas)
    endif()
else()
    include(${Open3D_3RDPARTY_DIR}/mkl/mkl.cmake)
    # MKL, cuSOLVER, cuBLAS
    # We link MKL statically. For MKL link flags, refer to:
    # https://software.intel.com/content/www/us/en/develop/articles/intel-mkl-link-line-advisor.html
    message(STATUS "Using MKL to support BLAS and LAPACK functionalities.")
    open3d_import_3rdparty_library(3rdparty_mkl
        HIDDEN
        INCLUDE_DIRS ${STATIC_MKL_INCLUDE_DIR}
        LIB_DIR      ${STATIC_MKL_LIB_DIR}
        LIBRARIES    ${STATIC_MKL_LIBRARIES}
        DEPENDS      ext_tbb ext_mkl_include ext_mkl
    )
    if(UNIX)
        target_compile_options(3rdparty_mkl INTERFACE "$<$<COMPILE_LANGUAGE:CXX>:-m64>")
        target_link_libraries(3rdparty_mkl INTERFACE Open3D::3rdparty_threads ${CMAKE_DL_LIBS})
    endif()
    target_compile_definitions(3rdparty_mkl INTERFACE "$<$<COMPILE_LANGUAGE:CXX>:MKL_ILP64>")
    # cuSOLVER and cuBLAS
    if(BUILD_CUDA_MODULE)
        # target_link_libraries(3rdparty_mkl INTERFACE CUDA::cublas_static CUDA::cublasLt_static CUDA::cusolver_static)  # Missing a lot
        # target_link_libraries(3rdparty_mkl INTERFACE CUDA::cublas_static CUDA::cusolver_static CUDA::cublasLt_static)  # Missing quite a lot

        # target_link_libraries(3rdparty_mkl INTERFACE CUDA::cublasLt_static CUDA::cublas_static CUDA::cusolver_static)  # Missing a lot
        # target_link_libraries(3rdparty_mkl INTERFACE CUDA::cublasLt_static CUDA::cusolver_static CUDA::cublas_static)  # Missing quite a lot

        # target_link_libraries(3rdparty_mkl INTERFACE CUDA::cusolver_static CUDA::cublas_static CUDA::cublasLt_static)  # Missing 5
        # target_link_libraries(3rdparty_mkl INTERFACE CUDA::cusolver_static CUDA::cublasLt_static CUDA::cublas_static)  # Missing quite a lot

        target_link_libraries(3rdparty_mkl INTERFACE
            CUDA::cusolver_static
            /usr/local/cuda/lib64/liblapack_static.a
            CUDA::cusparse_static
            CUDA::cublas_static
            CUDA::cublasLt_static
            CUDA::culibos

            # CUDA::cudart_static
            # CUDA::culibos
            # CUDA::lapack_static
            # CUDA::metis_static
            # CUDA::cublas_static

            # cmake          : https://cmake.org/cmake/help/latest/module/FindCUDAToolkit.html
            # cusolver latest: https://docs.nvidia.com/cuda/cusolver/index.html#link-dependency
            # cusolver 11.0  : https://docs.nvidia.com/cuda/archive/11.0/cusolver/index.html#static-link-lapack
            # cublas 11.0    : https://docs.nvidia.com/cuda/archive/11.0/cublas/index.html#cublasLt-general-description

            # libcudart_static.a, libculibos.a liblapack_static.a, libmetis_static.a, libcublas_static.a and libcusparse_static.a.
            # /home/yixing/repo/Open3D/cuda_lib/lib/libcuda_merged.a
        )
    endif()
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_mkl)
endif()

# Faiss
if (WITH_FAISS AND WIN32)
    message(STATUS "Faiss is not supported on Windows")
    set(WITH_FAISS OFF)
elseif(WITH_FAISS)
    message(STATUS "Building third-party library faiss from source")
    include(${Open3D_3RDPARTY_DIR}/faiss/faiss_build.cmake)
endif()
if (WITH_FAISS)
    if (USE_BLAS)
        if (BLAS_BUILD_FROM_SOURCE)
            set(FAISS_EXTRA_DEPENDENCIES 3rdparty_openblas)
        endif()
    else()
        set(FAISS_EXTRA_LIBRARIES ${STATIC_MKL_LIBRARIES})
        set(FAISS_EXTRA_DEPENDENCIES 3rdparty_mkl)
    endif()
    open3d_import_3rdparty_library(3rdparty_faiss
        INCLUDE_DIRS ${FAISS_INCLUDE_DIR}
        LIBRARIES    ${FAISS_LIBRARIES} ${FAISS_EXTRA_LIBRARIES}
        LIB_DIR      ${FAISS_LIB_DIR}
        DEPENDS      ext_faiss ${FAISS_EXTRA_DEPENDENCIES}
    )
    target_link_libraries(3rdparty_faiss INTERFACE ${CMAKE_DL_LIBS})
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_faiss)
endif()

# NPP
if (BUILD_CUDA_MODULE)
    # NPP library list: https://docs.nvidia.com/cuda/npp/index.html
    open3d_find_package_3rdparty_library(3rdparty_cuda_npp
        REQUIRED
        PACKAGE CUDAToolkit
        TARGETS CUDA::nppc_static CUDA::nppicc_static CUDA::nppif_static CUDA::nppig_static CUDA::nppim_static CUDA::nppial_static
    )
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_cuda_npp)
endif ()

# IPP
if (WITH_IPPICV)
    # Ref: https://stackoverflow.com/a/45125525
    set(IPPICV_SUPPORTED_HW AMD64 x86_64 x64 x86 X86 i386 i686)
    # Unsupported: ARM64 aarch64 armv7l armv8b armv8l ...
    if (NOT CMAKE_HOST_SYSTEM_PROCESSOR IN_LIST IPPICV_SUPPORTED_HW)
        set(WITH_IPPICV OFF)
        message(WARNING "IPP-ICV disabled: Unsupported Platform.")
    else ()
        include(${Open3D_3RDPARTY_DIR}/ippicv/ippicv.cmake)
        if (WITH_IPPICV)
            message(STATUS "IPP-ICV ${IPPICV_VERSION_STRING} available. Building interface wrappers IPP-IW.")
            open3d_import_3rdparty_library(3rdparty_ippicv
                HIDDEN
                INCLUDE_DIRS ${IPPICV_INCLUDE_DIR}
                LIBRARIES    ${IPPICV_LIBRARIES}
                LIB_DIR      ${IPPICV_LIB_DIR}
                DEPENDS      ext_ippicv
            )
            target_compile_definitions(3rdparty_ippicv INTERFACE ${IPPICV_DEFINITIONS})
            list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_ippicv)
        endif()
    endif()
endif ()

# Stdgpu
if (BUILD_CUDA_MODULE)
    include(${Open3D_3RDPARTY_DIR}/stdgpu/stdgpu.cmake)
    open3d_import_3rdparty_library(3rdparty_stdgpu
        INCLUDE_DIRS ${STDGPU_INCLUDE_DIRS}
        LIB_DIR      ${STDGPU_LIB_DIR}
        LIBRARIES    ${STDGPU_LIBRARIES}
        DEPENDS      ext_stdgpu
    )
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_stdgpu)
endif ()

# WebRTC
if(BUILD_WEBRTC)
    # Incude WebRTC headers in Open3D.h.
    set(BUILD_WEBRTC_COMMENT "")

    # Build WebRTC from source for advanced users.
    option(BUILD_WEBRTC_FROM_SOURCE "Build WebRTC from source" OFF)
    mark_as_advanced(BUILD_WEBRTC_FROM_SOURCE)

    # WebRTC
    if(BUILD_WEBRTC_FROM_SOURCE)
        include(${Open3D_3RDPARTY_DIR}/webrtc/webrtc_build.cmake)
    else()
        include(${Open3D_3RDPARTY_DIR}/webrtc/webrtc_download.cmake)
    endif()
    open3d_import_3rdparty_library(3rdparty_webrtc
        HIDDEN
        INCLUDE_DIRS ${WEBRTC_INCLUDE_DIRS}
        LIB_DIR      ${WEBRTC_LIB_DIR}
        LIBRARIES    ${WEBRTC_LIBRARIES}
        DEPENDS      ext_webrtc_all
    )
    target_link_libraries(3rdparty_webrtc INTERFACE Open3D::3rdparty_threads ${CMAKE_DL_LIBS})
    if (MSVC) # https://github.com/iimachines/webrtc-build/issues/2#issuecomment-503535704
        target_link_libraries(3rdparty_webrtc INTERFACE secur32 winmm dmoguids wmcodecdspuuid msdmo strmiids)
    endif()
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_webrtc)

    # CivetWeb server
    include(${Open3D_3RDPARTY_DIR}/civetweb/civetweb.cmake)
    open3d_import_3rdparty_library(3rdparty_civetweb
        INCLUDE_DIRS ${CIVETWEB_INCLUDE_DIRS}
        LIB_DIR      ${CIVETWEB_LIB_DIR}
        LIBRARIES    ${CIVETWEB_LIBRARIES}
        DEPENDS      ext_civetweb
    )
    list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_civetweb)
else()
    # Don't incude WebRTC headers in Open3D.h.
    set(BUILD_WEBRTC_COMMENT "//")
endif()

# embree
include(${Open3D_3RDPARTY_DIR}/embree/embree.cmake)
open3d_import_3rdparty_library(3rdparty_embree
    HIDDEN
    INCLUDE_DIRS ${EMBREE_INCLUDE_DIRS}
    LIB_DIR      ${EMBREE_LIB_DIR}
    LIBRARIES    ${EMBREE_LIBRARIES}
    DEPENDS      ext_embree
)
list(APPEND Open3D_3RDPARTY_PRIVATE_TARGETS Open3D::3rdparty_embree)
