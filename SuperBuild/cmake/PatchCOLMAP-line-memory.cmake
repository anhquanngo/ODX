# GCC 13+ / libstdc++ no longer transitively provides <memory> for std::unique_ptr.
# COLMAP 3.9.1 line.cc uses std::unique_ptr without including <memory>.

if(NOT DEFINED COLMAP_LINE_CC)
  message(FATAL_ERROR "COLMAP_LINE_CC is not set")
endif()

if(NOT EXISTS "${COLMAP_LINE_CC}")
  message(FATAL_ERROR "COLMAP line.cc not found: ${COLMAP_LINE_CC}")
endif()

file(READ "${COLMAP_LINE_CC}" _content)

if(_content MATCHES "#include <memory>")
  message(STATUS "COLMAP: line.cc already includes <memory>")
else()
  string(REPLACE "#include \"colmap/util/logging.h\""
    "#include \"colmap/util/logging.h\"\n\n#include <memory>"
    _content "${_content}")
  file(WRITE "${COLMAP_LINE_CC}" "${_content}")
  message(STATUS "COLMAP: added #include <memory> to line.cc")
endif()
