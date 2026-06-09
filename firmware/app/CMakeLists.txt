# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

set(ASSURELOOP_VERSION "0.1.0-dev" CACHE STRING "AssureLoop release version")
set(ASSURELOOP_PRODUCT "assureloop-controller-demo" CACHE STRING "AssureLoop product name")
set(ASSURELOOP_BUILD_PROFILE "dev" CACHE STRING "AssureLoop build profile")
set(ASSURELOOP_GIT_SHA "unknown" CACHE STRING "Source git commit")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(assureloop_controller_demo VERSION 0.1.0 LANGUAGES C)

zephyr_compile_definitions(
  ASSURELOOP_VERSION="${ASSURELOOP_VERSION}"
  ASSURELOOP_PRODUCT="${ASSURELOOP_PRODUCT}"
  ASSURELOOP_BUILD_PROFILE="${ASSURELOOP_BUILD_PROFILE}"
  ASSURELOOP_GIT_SHA="${ASSURELOOP_GIT_SHA}"
)

target_include_directories(app PRIVATE include)
target_sources(app PRIVATE
  src/main.c
  src/release.c
  src/telemetry.c
)
