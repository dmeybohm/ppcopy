cmake_minimum_required(VERSION 3.10)
include_directories(.)

set(CMAKE_BUILD_TYPE Debug)

# set the project name
project(ppcopy)

# add the executable
add_executable(simple-copy simple-copy.c)
add_executable(par-write par-write.c)
