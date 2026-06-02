cmake_minimum_required(VERSION 3.13)

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/gcc_toolchain.cmake")
endif()

project(corejack_sw LANGUAGES C ASM)

if(CMAKE_BUILD_TYPE STREQUAL "")
  get_property(helpstring CACHE CMAKE_BUILD_TYPE PROPERTY HELPSTRING)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "${helpstring}" FORCE)
endif()

set(COREJACK_TARGET "fpga" CACHE STRING "Software target platform: fpga or sim")
set_property(CACHE COREJACK_TARGET PROPERTY STRINGS fpga sim)
set(COREJACK_CORE "ibex" CACHE STRING "Selected SoC core")
set(COREJACK_BOARD "axku5" CACHE STRING "Selected FPGA board")
set(COREJACK_MARCH "rv32imc" CACHE STRING "RISC-V -march value")
set(COREJACK_MABI "ilp32" CACHE STRING "RISC-V -mabi value")
set(COREJACK_CORE_CLK_HZ "25000000" CACHE STRING "Firmware-visible core clock in Hz")
set(COREJACK_UART_BAUD "115200" CACHE STRING "Firmware-visible UART baud rate")
set(COREJACK_RAM_BYTES "1048576" CACHE STRING "Total board SRAM in bytes (drives the linker RAM region)")

# Generate the linker script for the selected board's RAM size. The stack
# occupies the top COREJACK_STACK_BYTES of RAM; code/data use the remainder.
# Default 1 MiB reproduces the historical link.ld byte-for-byte.
set(COREJACK_STACK_BYTES_DEC 32768)
math(EXPR _ram_region_bytes "${COREJACK_RAM_BYTES} - ${COREJACK_STACK_BYTES_DEC}" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR _stack_origin "2147483648 + (${COREJACK_RAM_BYTES} - ${COREJACK_STACK_BYTES_DEC})" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR _stack_bytes "${COREJACK_STACK_BYTES_DEC}" OUTPUT_FORMAT HEXADECIMAL)
set(COREJACK_RAM_REGION_BYTES "${_ram_region_bytes}")
set(COREJACK_STACK_ORIGIN "${_stack_origin}")
set(COREJACK_STACK_BYTES "${_stack_bytes}")
set(COREJACK_LINKER_SCRIPT "${CMAKE_BINARY_DIR}/link.ld")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/../common/link.ld.in" "${COREJACK_LINKER_SCRIPT}" @ONLY)

set(COREJACK_RISCV_FLAGS
  "-march=${COREJACK_MARCH}"
  "-mabi=${COREJACK_MABI}"
  "-mcmodel=medany"
)

if(COREJACK_TARGET STREQUAL "sim")
  set(SIM_CTRL_ENABLE 1)
elseif(COREJACK_TARGET STREQUAL "fpga")
  set(SIM_CTRL_ENABLE 0)
else()
  message(FATAL_ERROR "Unsupported COREJACK_TARGET='${COREJACK_TARGET}'. Expected 'fpga' or 'sim'.")
endif()

if(COREJACK_CORE STREQUAL "cv32e40s")
  set(COREJACK_RESET_AT_VECTOR_BASE 1)
else()
  set(COREJACK_RESET_AT_VECTOR_BASE 0)
endif()

if(COREJACK_CORE STREQUAL "serv" OR COREJACK_CORE STREQUAL "picorv32" OR COREJACK_CORE STREQUAL "cvw")
  set(COREJACK_HAS_JTAG_DEBUG 0)
else()
  set(COREJACK_HAS_JTAG_DEBUG 1)
endif()

add_subdirectory(common)

file(GLOB app_main_files CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "*/main.c")
foreach(app_main ${app_main_files})
  get_filename_component(app_dir "${app_main}" DIRECTORY)
  if(app_dir STREQUAL "common")
    continue()
  endif()

  add_executable("${app_dir}" "${app_main}")
  set_target_properties("${app_dir}" PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/${app_dir}"
  )
  target_compile_options("${app_dir}" PRIVATE ${COREJACK_RISCV_FLAGS})
  set_property(TARGET "${app_dir}" APPEND_STRING PROPERTY
    LINK_FLAGS " -march=${COREJACK_MARCH} -mabi=${COREJACK_MABI} -mcmodel=medany -T \"${COREJACK_LINKER_SCRIPT}\""
  )
  set_property(TARGET "${app_dir}" APPEND PROPERTY LINK_DEPENDS "${COREJACK_LINKER_SCRIPT}")
  target_link_libraries("${app_dir}" common gcc)
  target_compile_definitions("${app_dir}" PRIVATE
    COREJACK_TARGET="${COREJACK_TARGET}"
    COREJACK_CORE="${COREJACK_CORE}"
    COREJACK_BOARD="${COREJACK_BOARD}"
    COREJACK_CORE_CLK_HZ=${COREJACK_CORE_CLK_HZ}u
    COREJACK_UART_BAUD=${COREJACK_UART_BAUD}u
    COREJACK_HAS_JTAG_DEBUG=${COREJACK_HAS_JTAG_DEBUG}
  )
endforeach()
