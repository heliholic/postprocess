# One test file per unit under test, mirroring that unit's location in src/.

target_sources(rfx_tests PRIVATE
    core_test.cpp
    smoke_test.cpp
    version_test.cpp
)
