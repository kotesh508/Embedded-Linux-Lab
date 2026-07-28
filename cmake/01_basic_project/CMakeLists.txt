cmake_minimum_required(VERSION 3.10)

project(CMake_UART C)

set(CMAKE_C_STANDARD 11)

include_directories(include)

add_executable(uart_app
    src/main.c
    src/uart.c
)
