# Copyright 2022-2023 Mitchell. See LICENSE.

cmake_minimum_required(VERSION 3.16)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED true)
if(APPLE)
	set(CMAKE_OSX_DEPLOYMENT_TARGET 11 CACHE STRING "")
endif()

set(src ${CMAKE_SOURCE_DIR})

# Dependencies.
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)
set(lua_socket_zip v3.0-rc1.zip)
FetchContent_Declare(lua_socket
	URL https://github.com/diegonehab/luasocket/archive/${lua_socket_zip}
	PATCH_COMMAND patch -N -p1 < ${src}/luasocket.patch)
FetchContent_MakeAvailable(lua_socket)
set(mobdebug_zip 0.80.zip)
FetchContent_Declare(mobdebug URL https://github.com/pkulchenko/MobDebug/archive/${mobdebug_zip})
FetchContent_MakeAvailable(mobdebug)
set(deps_dir ${CMAKE_BINARY_DIR}/_deps)
set(dkjson_tgz dkjson-2.5.tar.gz)
set(dkjson_url file://${deps_dir}/${dkjson_tgz})
if(NOT EXISTS ${deps_dir}/${dkjson_tgz})
	set(dkjson_url http://dkolf.de/src/dkjson-lua.fsl/tarball/${dkjson_tgz})
endif()
FetchContent_Declare(dkjson URL ${dkjson_url})
FetchContent_MakeAvailable(dkjson)
set(lua_tgz lua-5.4.4.tar.gz)
set(lua_url file://${CMAKE_BINARY_DIR}/_deps/${lua_tgz})
if(NOT EXISTS ${CMAKE_BINARY_DIR}/_deps/${lua_tgz})
	set(lua_url https://www.lua.org/ftp/${lua_tgz})
endif()
FetchContent_Declare(lua URL ${lua_url})
FetchContent_MakeAvailable(lua)

# Build.
project(debugger LANGUAGES CXX C)
file(GLOB lua_socket_src ${lua_socket_SOURCE_DIR}/src/*.c)
list(FILTER lua_socket_src EXCLUDE REGEX "(mime|serial|unix)\.c$")
if(NOT WIN32)
	list(FILTER lua_socket_src EXCLUDE REGEX "wsocket\.c$")
else()
	list(FILTER lua_socket_src EXCLUDE REGEX "usocket\.c$")
endif()
if(WIN32)
	# On Windows, DLLs cannot do dynamic lookup. They need symbols to link to at build time.
	# Rather than fetching a Textadept build and creating separate DLLs linked to textadept.lib and
	# textadept-curses.lib, just embed a minimal copy of Lua in a single DLL.
	file(GLOB lua_src ${lua_SOURCE_DIR}/src/*.c)
	list(FILTER lua_src EXCLUDE REGEX "(lua|luac|[^x]lib|linit)\.c$") # of *lib.c, keep only lauxlib.c
endif()
add_library(core SHARED ${lua_socket_src} ${lua_src})
target_include_directories(core PRIVATE ${lua_socket_SOURCE_DIR}/src ${lua_SOURCE_DIR}/src)
if(NOT (WIN32 OR APPLE))
	target_compile_definitions(core PRIVATE LUASOCKET_NODEBUG LUA_NOCOMPAT_MODULE)
elseif(WIN32)
	target_compile_definitions(core PRIVATE WIN32 NDEBUG _WINDOWS _USRDLL _WINDLL LUA_NOCOMPAT_MODULE
		LUA_BUILD_AS_DLL LUA_LIB)
	target_link_libraries(core PRIVATE ws2_32)
elseif(APPLE)
	target_compile_definitions(core PRIVATE LUASOCKET_NODEBUG UNIX_HAS_SUN_LEN LUA_NOCOMPAT_MODULE)
	target_link_options(core PRIVATE -undefined dynamic_lookup)
endif()

# Install.
set(lib_dir ${src}/lua/socket)
install(TARGETS core DESTINATION ${lib_dir})
if(NOT (WIN32 OR APPLE))
	install(CODE "file(RENAME ${lib_dir}/libcore.so ${lib_dir}/core.so)")
elseif(APPLE)
	install(CODE "file(RENAME ${lib_dir}/libcore.dylib ${lib_dir}/coreosx.so)")
endif()
install(FILES ${lua_socket_SOURCE_DIR}/src/socket.lua ${mobdebug_SOURCE_DIR}/src/mobdebug.lua
	DESTINATION ${src}/lua)
install(FILES ${dkjson_SOURCE_DIR}/dkjson.lua DESTINATION ${src})
if(NOT (WIN32 OR APPLE))
	include(GNUInstallDirs)
	set(module_dir ${CMAKE_INSTALL_FULL_DATADIR}/textadept/modules/debugger)
	install(CODE "file(MAKE_DIRECTORY ${module_dir})")
	install(FILES init.lua dkjson.lua DESTINATION ${module_dir})
	install(DIRECTORY gdb go lua DESTINATION ${module_dir})
endif()

# Documentation.
get_filename_component(ta_dir ${src}/../../ ABSOLUTE)
add_custom_target(docs DEPENDS README.md)
add_custom_command(OUTPUT ${src}/README.md
	COMMAND ldoc --filter markdowndoc.ldoc ${src}/init.lua > ${src}/README.md
	COMMAND sed -i -e "1,+4d" -e "6c# Debugger" -e "7d" -e "s/^##/#/;" ${src}/README.md
	DEPENDS init.lua
	WORKING_DIRECTORY ${ta_dir}/scripts
	VERBATIM)
