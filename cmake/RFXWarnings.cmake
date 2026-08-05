# Shared warning configuration. Applied to first-party targets only, never to
# anything under ext/.

function(rfx_apply_warnings target)
    set(warnings
        -Wall
        -Wextra
        -Wshadow
        -Wconversion
        -Wsign-conversion
        -Wformat=2
        -Wundef
        -Wcast-align
        -Wcast-qual
        -Wnull-dereference
    )

    set(cxx_warnings
        -Wnon-virtual-dtor
        -Woverloaded-virtual
        -Wold-style-cast
        -Wuseless-cast
    )

    # C only: GCC rejects both for C++, where the first is spelled
    # -Wmissing-declarations and the second has no meaning.
    #
    # A non-static function with no prior declaration is usually one that should
    # have been static, and a stray global can override a weak vector by
    # accident. A file exporting symbols outside the tree — names newlib
    # declares only while building itself — writes its own prototypes.
    set(c_warnings
        -Wstrict-prototypes
    )

    # Firmware math is float; no MCU enables the double-precision FPU. A float
    # widened to double — passed to sqrt() rather than sqrtf(), or mixed with a
    # bare 1.0 literal — is an error on every build, not a warning promoted by
    # RFX_WERROR. A link-time check catches what the compiler cannot see.
    target_compile_options(${target} PRIVATE
        ${warnings}
        $<$<COMPILE_LANGUAGE:C>:${c_warnings}>
        $<$<COMPILE_LANGUAGE:CXX>:${cxx_warnings}>
        -Werror=double-promotion
        $<$<BOOL:${RFX_WERROR}>:-Werror>
    )
endfunction()
