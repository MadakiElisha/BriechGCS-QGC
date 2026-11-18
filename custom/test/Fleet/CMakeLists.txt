# Fleet C++ tests and tools, built on their own: Qt only, no QGC, no stock-file edits.
#
#   cmake -S custom/test/Fleet -B build/fleet-tests -DCMAKE_PREFIX_PATH=~/Qt/6.10.1/macos
#   cmake --build build/fleet-tests && ctest --test-dir build/fleet-tests --output-on-failure
#
# fleetlink_probe runs FleetLink against a real coordinator (see --help).

cmake_minimum_required(VERSION 3.22)
project(BriechFleetTests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network WebSockets Test)

set(FLEET_SRC ${CMAKE_CURRENT_SOURCE_DIR}/../../src/Fleet)
get_filename_component(BRIECH_REPO_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../.. ABSOLUTE)

add_library(FleetLinkCore STATIC
    ${FLEET_SRC}/FleetProtocol.cc
    ${FLEET_SRC}/FleetProtocol.h
    ${FLEET_SRC}/FleetLinkWorker.cc
    ${FLEET_SRC}/FleetLinkWorker.h
    ${FLEET_SRC}/FleetLink.cc
    ${FLEET_SRC}/FleetLink.h
    ${FLEET_SRC}/FleetModels.cc
    ${FLEET_SRC}/FleetModels.h
    ${FLEET_SRC}/FleetVehicleState.cc
    ${FLEET_SRC}/FleetVehicleState.h
    ${FLEET_SRC}/FleetOperatorActions.cc
    ${FLEET_SRC}/FleetOperatorActions.h
    ${FLEET_SRC}/FleetDataAge.cc
    ${FLEET_SRC}/FleetDataAge.h
    ${FLEET_SRC}/FleetAudit.cc
    ${FLEET_SRC}/FleetAudit.h
    ${FLEET_SRC}/FleetSnapshots.cc
    ${FLEET_SRC}/FleetSnapshots.h
)
target_include_directories(FleetLinkCore PUBLIC ${FLEET_SRC})
target_link_libraries(FleetLinkCore PUBLIC Qt6::Core Qt6::Gui Qt6::Network Qt6::WebSockets)

enable_testing()

foreach(test tst_FleetProtocol tst_FleetLink tst_FleetModels tst_FleetVehicleState tst_FleetOperatorActions tst_FleetDataAge tst_FleetAudit tst_FleetSnapshots)
    add_executable(${test} ${test}.cc)
    target_link_libraries(${test} PRIVATE FleetLinkCore Qt6::Test)
    target_compile_definitions(${test} PRIVATE BRIECH_REPO_DIR="${BRIECH_REPO_DIR}")
    add_test(NAME ${test} COMMAND ${test})
endforeach()

add_executable(fleetlink_probe fleetlink_probe.cc)
target_link_libraries(fleetlink_probe PRIVATE FleetLinkCore)

# Every message QGC sends, checked with the coordinator's own schema validator
# (check_outgoing.py). Needs a Python with ground-core's requirements, e.g.
#   -DPython3_EXECUTABLE=ground-core/.venv/Scripts/python.exe   (Windows)
#   -DPython3_EXECUTABLE=ground-core/.venv/bin/python           (Linux, macOS)
# CI sets BRIECH_REQUIRE_SCHEMA_CHECK so the check can never be skipped there.
add_executable(fleet_outgoing_samples fleet_outgoing_samples.cc)
target_link_libraries(fleet_outgoing_samples PRIVATE FleetLinkCore)

option(BRIECH_REQUIRE_SCHEMA_CHECK "Fail the configure when the outgoing-message schema check cannot run" OFF)
find_package(Python3 COMPONENTS Interpreter)
set(_schema_check_ok FALSE)
if(Python3_Interpreter_FOUND)
    execute_process(COMMAND ${Python3_EXECUTABLE} -c "import jsonschema, referencing"
                    RESULT_VARIABLE _schema_deps OUTPUT_QUIET ERROR_QUIET)
    if(_schema_deps EQUAL 0)
        set(_schema_check_ok TRUE)
    endif()
endif()
if(_schema_check_ok)
    add_test(NAME outgoing_messages_match_schemas
             COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/check_outgoing.py
                     --emitter $<TARGET_FILE:fleet_outgoing_samples>)
elseif(BRIECH_REQUIRE_SCHEMA_CHECK)
    message(FATAL_ERROR "outgoing-message schema check needs Python 3 with jsonschema and referencing "
                        "(pip install -r ground-core/requirements.txt)")
else()
    message(WARNING "Python 3 with jsonschema not found: outgoing_messages_match_schemas is not registered")
endif()
