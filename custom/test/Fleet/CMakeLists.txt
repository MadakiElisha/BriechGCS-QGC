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

find_package(Qt6 REQUIRED COMPONENTS Core Network WebSockets Test)

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
)
target_include_directories(FleetLinkCore PUBLIC ${FLEET_SRC})
target_link_libraries(FleetLinkCore PUBLIC Qt6::Core Qt6::Network Qt6::WebSockets)

enable_testing()

foreach(test tst_FleetProtocol tst_FleetLink tst_FleetModels tst_FleetVehicleState tst_FleetOperatorActions tst_FleetDataAge tst_FleetAudit)
    add_executable(${test} ${test}.cc)
    target_link_libraries(${test} PRIVATE FleetLinkCore Qt6::Test)
    target_compile_definitions(${test} PRIVATE BRIECH_REPO_DIR="${BRIECH_REPO_DIR}")
    add_test(NAME ${test} COMMAND ${test})
endforeach()

add_executable(fleetlink_probe fleetlink_probe.cc)
target_link_libraries(fleetlink_probe PRIVATE FleetLinkCore)
