cmake_minimum_required(VERSION 3.19)
project(Storybook)

set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (APPLE)
    set(MACOS_VERSION_MIN_FLAGS -mmacosx-version-min=10.14)
    set(CMAKE_OSX_ARCHITECTURES "x86_64")
endif()

find_package(
  Qt5
  COMPONENTS Core Quick QuickControls2 Test
  REQUIRED)

file(GLOB_RECURSE QML_FILES "stubs/*.qml" "mocks/*.qml" "pages/*.qml"
    "src/*.qml" "src/qmldir" "../ui/StatusQ/*.qml" "../ui/app/*.qml")
file(GLOB_RECURSE JS_FILES "../ui/StatusQ/*.js" "../ui/app/*.js")

set(PROJECT_LIB "${PROJECT_NAME}Lib")

add_library(${PROJECT_LIB}
    cachecleaner.cpp cachecleaner.h
    directorieswatcher.cpp directorieswatcher.h
    figmadecoratormodel.cpp figmadecoratormodel.h
    figmaio.cpp figmaio.h
    figmalinks.cpp figmalinks.h
    figmalinksmodel.cpp figmalinksmodel.h
    figmalinkssource.cpp figmalinkssource.h
    modelutils.cpp modelutils.h
    sectionsdecoratormodel.cpp sectionsdecoratormodel.h
)

add_executable(
  ${PROJECT_NAME}
  main.cpp
  main.qml PagesModel.qml
  ${QML_FILES}
  ${JS_FILES}
  figma.json
)

target_compile_definitions(${PROJECT_NAME}
                           PRIVATE QML_IMPORT_ROOT="${CMAKE_CURRENT_LIST_DIR}")

target_link_libraries(
    ${PROJECT_LIB} PUBLIC Qt5::Core Qt5::Quick Qt5::QuickControls2)
target_link_libraries(
    ${PROJECT_NAME} PRIVATE ${PROJECT_LIB} SortFilterProxyModel)

enable_testing()

add_executable(SectionsDecoratorModelTest tests/tst_SectionsDecoratorModel.cpp)
target_link_libraries(SectionsDecoratorModelTest PRIVATE Qt5::Test ${PROJECT_LIB})
add_test(NAME SectionsDecoratorModelTest COMMAND SectionsDecoratorModelTest)

add_executable(FigmaDecoratorModelTest tests/tst_FigmaDecoratorModel.cpp)
target_link_libraries(FigmaDecoratorModelTest PRIVATE Qt5::Test ${PROJECT_LIB})
add_test(NAME FigmaModelTest COMMAND FigmaModelTest)

list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/../ui/StatusQ/src")
list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/../ui/app")
list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/../ui/imports")
list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/src")
list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/pages")
list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/stubs")
list(APPEND QML_DIRS "${CMAKE_SOURCE_DIR}/mocks")
set(QML_IMPORT_PATH "${QML_DIRS}" CACHE STRING "Qt Creator extra QML import paths" FORCE)

if (APPLE)
  find_library(AppKit AppKit)
  find_library(Foundation Foundation)

  target_link_libraries(${PROJECT_NAME} PRIVATE ${AppKit} ${Foundation})
endif()

add_subdirectory(../ui/StatusQ/vendor/SortFilterProxyModel ./SortFilterProxyModel)
