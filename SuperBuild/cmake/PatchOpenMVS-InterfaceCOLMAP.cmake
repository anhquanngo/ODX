# Enable InterfaceCOLMAP in WebODM/openMVS (tag 355 ships it commented out in apps/CMakeLists.txt).
# Required for ODX --sfm-engine colmap (COLMAP sparse -> OpenMVS scene.mvs).

if(NOT DEFINED OPENMVS_APPS_CMAKE)
  message(FATAL_ERROR "OPENMVS_APPS_CMAKE is not set")
endif()

if(NOT EXISTS "${OPENMVS_APPS_CMAKE}")
  message(FATAL_ERROR "OpenMVS apps CMakeLists not found: ${OPENMVS_APPS_CMAKE}")
endif()

file(READ "${OPENMVS_APPS_CMAKE}" _content)

if(_content MATCHES "#ADD_SUBDIRECTORY\\(InterfaceCOLMAP\\)")
  string(REPLACE "#ADD_SUBDIRECTORY(InterfaceCOLMAP)" "ADD_SUBDIRECTORY(InterfaceCOLMAP)" _content "${_content}")
  file(WRITE "${OPENMVS_APPS_CMAKE}" "${_content}")
  message(STATUS "OpenMVS: enabled InterfaceCOLMAP in apps/CMakeLists.txt")
elseif(_content MATCHES "ADD_SUBDIRECTORY\\(InterfaceCOLMAP\\)")
  message(STATUS "OpenMVS: InterfaceCOLMAP already enabled in apps/CMakeLists.txt")
else()
  message(WARNING "OpenMVS: InterfaceCOLMAP entry not found in apps/CMakeLists.txt")
endif()
