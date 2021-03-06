#
# Copyright 2018, Data61
# Commonwealth Scientific and Industrial Research Organisation (CSIRO)
# ABN 41 687 119 230.
#
# This software may be distributed and modified according to the terms of
# the BSD 2-Clause license. Note that NO WARRANTY is provided.
# See "LICENSE_BSD2.txt" for details.
#
# @TAG(DATA61_BSD)
#

cmake_minimum_required(VERSION 3.7.2)

include(ExternalProject)

include(${KERNEL_HELPERS_PATH})

set(configure_string "")

config_string(CAmkESDefaultStackSize CAMKES_DEFAULT_STACK_SIZE
    "Stack size to allocate per-component, in bytes. Note that this value
    should be page-aligned. If not, it will be rounded up."
    DEFAULT 16384
    UNQUOTE
)

config_string(CAmkESDefaultHeapSize CAMKES_DEFAULT_HEAP_SIZE
    "Heap size to allocate per-component, in bytes."
    DEFAULT 1048576
    UNQUOTE
)

config_choice(CAmkESErrorHandlingMode CAMKES_ERROR_HANDLING_MODE
    "Select the mode of error handling used in the glue code. It should only
    be necessary to adjust this setting if you are doing verification.
    Otherwise, the default error handling mechanism allows for
    configuration at runtime.

    Standard -> Standard error handling mechanism, that is configurable by the user at
    runtime. See the documentation for details of the API for this.

    Guards -> Use verification-visible guards at the site of each potential error.
    Note that this assumes that none of the error conditions are possible.
    If you are trying to verify code, you will be forced to prove that none
    of the error conditions can ever actually occur.

    Abort -> Call 'abort' inline when an error occurs. For debugging purposes, this
    is probably not the behaviour you want as it will give you no
    information about the error. The standard error handling mechanism has
    a nicer default for debugging. This mode is primarily useful when you
    want to verify code whose error handlers are unreachable for
    non-trivial reasons.

    Discard -> Perform the 'discard' action on any error that occurs. The advantage of
    this over simply configuring this behaviour via the standard mechanism
    is that you will not need to reason about any of the complicated error
    handling structures or control flow. This has no implementation
    advantages over the standard mechanism."
    "Standard;CAmkESErrorHandlingConfigurable;CAMKES_ERROR_HANDLER_CONFIGURABLE"
    "Guards;CAmkESErrorHandlingGuard;CAMKES_ERROR_HANDLER_GUARD"
    "Abort;CAmkESErrorHandlingAbort;CAMKES_ERROR_HANDLER_ABORT"
    "Discard;CAmkESErrorHandlingDiscard;CAMKES_ERROR_HANDLER_DISCARD"
)

config_option(CAmkESConnectorTiming CAMKES_CONNECTOR_TIMING
    "Enable timing points within connector templates that take cycle counter
    values as they are passed. This timing data can then be retrieved after
    execution."
    DEFAULT OFF
)

config_option(CAmkESProvideTCBCaps CAMKES_PROVIDE_TCB_CAPS
    "Hand out TCB caps to components. These caps are used by the component
    to exit cleanly by suspending. Disabling this option leaves components
    with an empty slot in place of their TCB cap. This means they will cap
    fault when attempting to exit. The advantage is that your resulting
    CapDL specification contains no TCB caps and is thus easier to reason
    about."
    DEFAULT ON
)

config_choice(CAmkESTLSModel CAMKES_TLS_MODEL
    "The CAmkES glue code uses thread-local variables for marshalling and
    unmarshalling of RPC parameters. This setting controls how this thread-
    local storage is implemented.

    standard -> Allocate thread-local variables on the stack or the heap as appropriate.
    This is the default and will hold the fewest surprises for C
    programmers.

    per-thread -> Allocate per-thread global variables for use as thread-local storage.
    The main purpose of this implementation is to avoid taking the address
    of local variables, an idiom that cannot be handled by the verification
    C parser."
    "standard;CAmkESTLSStandard;CAMKES_TLS_STANDARD"
    "per-thread;CAmkESTLSPerThreadGlobal;CAMKES_TLS_PTG"
)

config_string(CAmkESDefaultPriority CAMKES_DEFAULT_PRIORITY
    "Default priority for component threads if this is not overridden via an
    attribute. Generally you want to set this as high as possible due to
    the suboptimal seL4 scheduler."
    # Default to one less than max prio to avoid interleaving with the CapDL intialiser
    DEFAULT 254
    UNQUOTE
)
if ((${CAmkESDefaultPriority} LESS 0) OR (${CAmkESDefaultPriority} GREATER 255))
    message(FATAL_ERROR "CAmkESDefaultPriority must be [0, 255]")
endif()

add_config_library(camkes_config "${configure_string}")

# These options are not declared with the config_* system because they only need to exist
# in the build system, and not appear in a configuration library
set(CAmkESCPP OFF CACHE BOOL
    "Run CPP on the input specification(s) before parsing them into an AST.
    This can allow you to write parameterised specs in the case of more
    complex system"
)

set(CAmkESImportPath "" CACHE STRING
    "CAmkES can include components and interfaces stored outside the current application
    directory. This option is a space delimited list of absolute paths to directories
    to be searched for components or interfaces included with angle brackets."
)

set(CAmkESDefaultAffinity 0 CACHE STRING
    # Default to 0 as this is the index assigned to the BSP (Boot Strap Processor) by seL4
    "Default affinity for component threads if this is not overridden via an
    attribute. Think carefully when organizing your applications for
    multiprocessor operation"
)
math(EXPR MaxNumNodesMin1 "${KernelMaxNumNodes} - 1")
if((${CAmkESDefaultAffinity} < 0) OR (${CAmkESDefaultAffinity} GREATER ${MaxNumNodesMin1}))
    message(FATAL_ERROR "Invalid CAmkESDefaultAffinity")
endif()

set(CAmkESAllowForwardReferences OFF CACHE BOOL
    "By default, you can only refer to objects in your specification which
    have been defined before the point at which you reference them.
    Selecting this option allows you to also reference objects that are
    defined below the point at which the reference occurs. This option is
    off by default because it leads to a slight performance degradation in
    parsing specification"
)

set(CAmkESObjdumpMethod "auto" CACHE STRING
    "Instead of using the internal ELF parsing functionality, it is
    possible to call out to your toolchain's objdump to perform
    required operations. This is more fragile than using internal
    functionality, but can provide a performance boost in compilation
    times. If you set this to auto (default), CAmkES will use your
    toolchain's objdump if it is in your PATH.

    off -> Disable the use of objdump for ELF symbol lookups. Lookups will be
    done via standard built-in CAmkES mechanisms. This may be slightly
    slower.

    auto -> Automatically detect whether objdump is available for use for ELF
    symbol lookups, and use it if so. This will result in the fastest
    available method for ELF symbol lookup being used automatically and
    is the recommended default.

    on -> Use objdump for ELF symbol lookups. Lookups will be done by calling
    out to your toolchain's objdump binary. This is fastest at the
    expense of some robustness."
)
set_property(CACHE CAmkESObjdumpMethod PROPERTY STRINGS "auto;on;off")

set(CAmkESCompilationCache ON CACHE BOOL
    "Enable caching of successful code generation. With this option
    selected, CAmkES will save the output of code generation and will
    first try to satisfy new code generation requests from this cached
    information."
)

set(CAmkESAccelerator ON CACHE BOOL
    "CAmkES comes with an optimised tool that can serve cached results
    from previous builds. Enabling this allows repeated builds to be
    completed without the overhead of running CAmkES itself or the
    Python interpreter. This option selects this tool for code
    generation before running CAmkES itself."
)

set(CAmkESRPCLockElision ON CACHE BOOL
    "Detect when it is safe to exclude locking operations in the seL4RPC connector and
    automatically do so. This is an optimisation that can improve the performance of
    this connector."
)

set(CAmkESSpecialiseSyscallStubs ON CACHE BOOL
    "Detect when glue code overhead could be reduced with a custom syscall
    stub and generate and use this instead of the libsel4 stubs. This does
    not affect whether a given IPC will hit the fastpath, but it does
    reduce the userlevel overhead of these system calls. In ideal
    conditions this will give you RPC as fast as native seL4 IPC. This only
    has an effect on ARM."
)

set(CAmkESLargeFramePromotion ON CACHE BOOL
    "Some hardware platforms support multiple page sizes. In components with
    large virtual address spaces, it is possible to reduce memory usage
    (and consequent load time) by backing the component's address space with
    pages of these larger sizes. When this setting is enabled, small
    consecutive page mappings will be promoted to fewer consecutive large
    mappings. Note that larger frame sizes are directly mapped into page
    directories and can also save the overhead of an accompanying page
    table."
)

set(CAmkESDMALargeFramePromotion OFF CACHE BOOL
    "For components with a configured DMA pool, the frames backing this
    are not automatically promoted to large frames even if the pool is
    sufficiently large. Select this option to enable such promotion
    automatically. This is off by default because it requires support
    for large alignments in your toolchain's assembler, which is often
    absent in ARM toolchains."
)

set(CAmkESPythonOptimisation "none" CACHE STRING
    "Select the optimisation flag to pass to the Python interpreter. The
    default is for no optimisation because profiling has suggested this
    has a detrimental effect for CAmkES. However, you may find
    different results depending on your wor

    none -> Do not pass any optimisation flags to the Python interpreter.

    -O -> Enable basic optimisations. This disables assertions and is not
    recommended if you are working on the internals of CAmkES itself.

    -OO -> Enable basic optimisations and also strip docstrings."
)
set_property(CACHE CAmkESPythonOptimisation PROPERTY STRINGS "none;-O;-OO")

set(CAmkESPythonInterpreter "cpython" CACHE STRING
    "Select the Python interpreter used for executing CAmkES. The default
    CPython interpreter should be acceptable for any normal use, but you
    may find PyPy provides better build system performance under some
    circumstances. To use PyPy, obviously you need it installed. The other
    interpreters are for profiling or dynamic analysis.

    cpython -> Use CPython, the default Python interpreter. This is what will be
    most familiar to Python users.

    cpython2 -> Force the use of Python 2, instead of the default Python
    executable.

    cpython3 -> Force the use of Python 3, instead of the default Python
    executable. Note that Python 3 support is currently experimental
    and should not be expected to work without tweaks.

    pypy -> Use PyPy, an optimised Python interpreter. PyPy is intended to be
    faster than CPython with maximum compatibility, but it is not
    recommended for use with CAmkES because profiling has indicated it
    is actually *slower* in general for CAmkES' workload.

    figleaf -> Use Figleaf, an interpreter that reports code coverage statistics.
    This interpreter is primarily useful for profiling or debugging
    CAmkES itself.

    coverage -> Use Python-coverage, an interpreter that reports code coverage
    statistics. This interpreter is primarily useful for profiling or
    debugging CAmkES itself."
)
set_property(CACHE CAmkESPythonInterpreter PROPERTY STRINGS "cpython;cpython2;cpython3;pypy;figleaf;coverage")

set(CAmkESFaultHandlers ON CACHE BOOL
    "When a component references invalid virtual memory or an invalid
    capability, the access generates a fault. With this option selected
    a handler is provided that decodes this fault for debugging
    purposes. You will want to disable this in a production system or in
    a system where you want to handle your own faults."
)

set(CAmkESSupportInit ON CACHE BOOL
    "Support the pre_init, post_init and interface init functions as part of
    component startup. These functions allow extra functionality, but
    introduce some endpoint caps for synchronisation. You probably want
    this option enabled unless you are targetting verification."
)

# TODO: The following options are not yet supported in cmake build template, as a result
# these are currently commented out to as not to confuse users. They should be uncommented
# as support is added
#set(CAmkESPruneGenerated OFF CACHE BOOL
#    "Prune generated C files
#    When selected, this option minimises the number of C functions in a
#    given generated file. This can be done because the CAmkES generation
#    logic knows which functions are required by the user's components and
#    which are not. This option implies a separate pre-process step on the
#    generated files prior to pruning/compilation, otherwise the generated
#    C files are already minimal. Note, you will need libclang-dev installed
#    to enable this option."
#)

#set(CAmkESThys OFF CACHE BOOL
#    "Generate correctness proofs
#    Generate AutoCorres-based theories of connector correctness during
#    compilation."
#)

#set(CAmkESUnifiedThy OFF CACHE BOOL
#    "Generate unified correctness proof
#    Generate an AutoCorred-based theory combining the two glue code halves
#    of a connector, resulting in a final correctness statement."
#    DEPENDS CAmkESPruneGenerated
#)

#set(CAmkESArchThy OFF CACHE BOOL
#    "Generate architectural specification
#    Generate an Isabelle theory specifying the architecture of the
#    system, using the l4.verified formal model of ADL."
#)

#set(CAmkESCImpThy OFF CACHE BOOL
#    "Generate dynamic behavioural specification
#    Generate an Isabelle theory specifying the dynamic behaviour of the
#    system. This theory builds on top of the CIMP formalisation."
#)

#set(CAmkESCapDLThy OFF CACHE BOOL
#    "Generate CapDL Isabelle specification
#    During a CAmkES build, a textual CapDL specification of the system
#    is generated for the purpose of initialisation. Selecting this
#    option causes an Isabelle version of this specification to be
#    generated as well for the purposes of reasoning about the
#    capability distribution of a CAmkES system"
#)

#set(CAmkESLabelMapping OFF CACHE BOOL
#    "Generate policy label mapping
#    Enable this option to generate a mapping from labels to kernel objects
#    during compilation. A label per-CAmkES entity (component instance or
#    connection) is generated and they are intended to form the input domain
#    of a function mapping these to final policy labels. The final labels
#    are then used to reason about the security properties of a system."
#)

set(CAmkESVerbose OFF CACHE BOOL
    "Enable verbose output from CAmkES. This is disabled by default as it
    can result in a lot of output, but is useful for debugging CAmkES problems"
)

# Save the path to to python-capdl whilst we know it
set(PYTHON_CAPDL_PATH "${CMAKE_CURRENT_SOURCE_DIR}/projects/capdl/python-capdl-tool")
set(CAPDL_TOOL_SOURCE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/projects/capdl/capDL-tool")

# Save the location of the camkes tool wrapper script
RequireFile(CAMKES_TOOL camkes.sh PATHS "${CMAKE_CURRENT_LIST_DIR}")

# Use the camkes script to determine the location of other things
get_filename_component(CAMKES_TOOL_DIR "${CAMKES_TOOL}" DIRECTORY)
set(CAMKES_TOOL_BUILTIN_DIR "${CAMKES_TOOL_DIR}/include/builtin")

# If requested install the camkes-accelerator into our local build directory and add
# it to the path
if (CAmkESAccelerator)
    # Need to give the camkes accelerator a path to the python-capdl-tool as camkes hashes
    # the contents of this if it is on the path in order to determine the current camkes 'version'
    # If this is not on the path then the accelerator build now, and the camkes invoked later,
    # will hash different files and hence disagree on the version
    ExternalProject_Add(external_camkes_accelerator
        SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tools/camkes/tools/accelerator"
        CMAKE_CACHE_ARGS "-DCMAKE_INSTALL_PREFIX:STRING=${CMAKE_CURRENT_BINARY_DIR}/accelerator"
        BUILD_COMMAND ${CMAKE_COMMAND} -E env "PYTHONPATH=$ENV{PYTHONPATH}:${PYTHON_CAPDL_PATH}" cmake --build .
        # I do not understand why cmake cannot work out when to rebuild this itself, especially given
        # that the target is also a cmake project, but given that the rebuild is quick we shall just
        # do it all the time
        BUILD_ALWAYS ON
    )
    set(ENV{PATH} "$ENV{PATH}:${CMAKE_CURRENT_BINARY_DIR}/accelerator/bin")
endif()

# Require the parse-capDL tool
ExternalProject_Add(parse_capdl_tool
    SOURCE_DIR "${CAPDL_TOOL_SOURCE_PATH}"
    CONFIGURE_COMMAND bash -c "cp -ra ${CAPDL_TOOL_SOURCE_PATH}/* ."
    BUILD_ALWAYS ON
    BUILD_COMMAND ${CMAKE_COMMAND} -E env "CONFIG_CAPDL_LOADER_MAX_IRQS=${CapDLLoaderMaxIRQs}" make
    INSTALL_COMMAND ${CMAKE_COMMAND} -E env "PATH=$ENV{PATH}:${CMAKE_CURRENT_BINARY_DIR}/parse_capdl_tool-prefix/src/parse_capdl_tool-build" make install
)
ExternalProject_Get_property(parse_capdl_tool BINARY_DIR)
set(CAPDL_TOOL_PATH "${BINARY_DIR}")

# Search for a FMT tool for reformatting generated CAmkES C files
find_program(CLANG_FORMAT_TOOL clang-format)
if ("${CLANG_FORMAT_TOOL}" STREQUAL "CLANG_FORMAT_TOOL-NOTFOUND")
    set(CAMKES_C_FMT_INVOCATION "")
else()
    set(CAMKES_C_FMT_INVOCATION "${CLANG_FORMAT_TOOL} --style=LLVM")
endif()

# Find the sponge tool, or emulate it
find_program(SPONGE_TOOL sponge)
if ("${SPONGE_TOOL}" STREQUAL "SPONGE_TOOL-NOTFOUND")
    set(CAMKES_SPONGE_INVOCATION "${CMAKE_COMMAND} -E ${CMAKE_CURRENT_BINARY_DIR}/sponge_emul.sh")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/sponge_emul.sh" "python -c 'import sys; data = sys.stdin.read(); f = open(sys.argv[1], \"w\"); f.write(data); f.close()' $@")
else()
    set(CAMKES_SPONGE_INVOCATION "${SPONGE_TOOL}")
endif()

# Find the Isabelle theory pre-process for formatting theory files
find_program(TPP_TOOL tpp PATHS tools/camkes/tools)
if ("${TPP_TOOL}" STREQUAL "TPP_TOOL-NOTFOUND")
    message(FATAL_ERROR "Failed to find tpp tool")
endif()

# CAmkES defines its own heaps and for this to work muslcsys must not be configured to
# use a static morecore. We make the morecore dynamic by setting the size to 0
set(LibSel4MuslcSysMorecoreBytes 0 CACHE STRING "" FORCE)

# Function to help build the CAMKES_TOOL_ENVIRONMENT below
function(camkes_append_env_if)
    # Loop through each pair of arguments and build the environment
    set(local_env "${CAMKES_TOOL_ENVIRONMENT}")
    math(EXPR limit "${ARGC} - 1")
    foreach(i RANGE 0 ${limit} 2)
        math(EXPR ip1 "${i} + 1")
        set(check "${ARGV${i}}")
        string(REGEX REPLACE " +" ";" check "${check}")
        if(${check})
            # Add the environment
            list(APPEND local_env "${ARGV${ip1}}=1")
        endif()
    endforeach()
    set(CAMKES_TOOL_ENVIRONMENT "${local_env}" PARENT_SCOPE)
endfunction(camkes_append_env_if)

function(camkes_append_flags)
    math(EXPR limit "${ARGC} - 1")
    set(local_flags "${CAMKES_FLAGS}")
    foreach(i RANGE 0 ${limit})
        set(list "${ARGV${i}}")
        list(GET list 0 check)
        string(REGEX REPLACE " +" ";" check "${check}")
        if(${check})
            list(GET list 1 when_true)
            list(APPEND local_flags "${when_true}")
        else()
            list(LENGTH list len)
            if (${len} GREATER 2)
                list(GET list 2 when_false)
                list(APPEND local_flags "${when_false}")
            endif()
        endif()
    endforeach()
    set(CAMKES_FLAGS "${local_flags}" PARENT_SCOPE)
endfunction(camkes_append_flags)

# This is called from the context of a CAmkES application that has decided what the 'root'
# application is. This function will effectively generate a rule for building the final
# rootserver image
function(DeclareCAmkESRootserver adl)
    cmake_parse_arguments(PARSE_ARGV 1 CAMKES_ROOT
        "" # Option arguments
        "" # Single arguments
        "CPP_FLAGS;CPP_INCLUDES" # Multiple aguments
    )
    # Stash this request as a global property. The main CAmkES build file will call
    # GenerateCAmkESRootserver later once all the build scripts are processed
    get_property(declared GLOBAL PROPERTY CAMKES_ROOT_DECLARED)
    if (declared)
        message(FATAL_ERROR "A CAmkES rootserver was already declared")
    endif()
    foreach(include IN LISTS CAMKES_ROOT_CPP_INCLUDES)
        get_absolute_source_or_binary(include "${include}")
        list(APPEND CAMKES_ROOT_CPP_FLAGS "-I${include}")
    endforeach()
    get_absolute_source_or_binary(adl "${adl}")
    set_property(GLOBAL PROPERTY CAMKES_ROOT_ADL "${adl}")
    set_property(GLOBAL PROPERTY CAMKES_ROOT_CPP_FLAGS "${CAMKES_ROOT_CPP_FLAGS}")
    set_property(GLOBAL PROPERTY CAMKES_ROOT_DECLARED TRUE)
endfunction(DeclareCAmkESRootserver)

# Called to actually generate the definitions for the CAmkES rootserver. Due to its
# use of properties for some configuration it needs to be run after all other build
# scripts, typically by the main CAmkES build file
function(GenerateCAmkESRootserver)
    # Retrieve properties from the declare call above
    get_property(declared GLOBAL PROPERTY CAMKES_ROOT_DECLARED)
    if (NOT declared)
        message(FATAL_ERROR "No CAmkES rootserver was declared")
    endif()
    get_property(adl GLOBAL PROPERTY CAMKES_ROOT_ADL)
    get_property(CAMKES_ROOT_CPP_FLAGS GLOBAL PROPERTY CAMKES_ROOT_CPP_FLAGS)
    set(CAMKES_TOOL_ENVIRONMENT "")
    set(CAMKES_TOOL_DEPENDENCIES "")
    # Build the environment expected by camkes, as well as the camkes.sh wrapper script
    list(APPEND CAMKES_TOOL_ENVIRONMENT "PYTHONPATH=$ENV{PYTHONPATH}:${PYTHON_CAPDL_PATH}")
    if (CAmkESAccelerator)
        list(APPEND CAMKES_TOOL_DEPENDENCIES "external_camkes_accelerator")
    endif()
    # List of 'if condition' 'definition to add' for building the environment exports
    camkes_append_env_if(
        CAmkESAccelerator CONFIG_CAMKES_ACCELERATOR
        "${CAmkESObjdumpMethod} STREQUAL on" CONFIG_CAMKES_USE_OBJDUMP_ON
        "${CAmkESObjdumpMethod} STREQUAL auto" CONFIG_CAMKES_USE_OBJDUMP_AUTO
        "${CAmkESPythonOptimisation} STREQUAL -O" CONFIG_CAMKES_PYTHON_OPTIMISE_BASIC
        "${CAmkESPythonOptimisation} STREQUAL -OO" CONFIG_CAMKES_PYTHON_OPTIMISE_MORE
        "${CAmkESPythonInterpreter} STREQUAL cpython" CONFIG_CAMKES_PYTHON_INTERPRETER_CPYTHON
        "${CAmkESPythonInterpreter} STREQUAL cpython2" CONFIG_CAMKES_PYTHON_INTERPRETER_CPYTHON2
        "${CAmkESPythonInterpreter} STREQUAL cpython3" CONFIG_CAMKES_PYTHON_INTERPRETER_CPYTHON3
        "${CAmkESPythonInterpreter} STREQUAL pypy" CONFIG_CAMKES_PYTHON_INTERPRETER_PYPY
        "${CAmkESPythonInterpreter} STREQUAL figleaf" CONFIG_CAMKES_PYTHON_INTERPRETER_FIGLEAF
        "${CAmkESPythonInterpreter} STREQUAL coverage" CONFIG_CAMKES_PYTHON_INTERPRETER_COVERAGE
    )
    # Use the path as constructed at generation time
    list(APPEND CAMKES_TOOL_ENVIRONMENT "PATH=$ENV{PATH}")
    get_filename_component(CAMKES_CDL_TARGET "${adl}" NAME_WE)
    set(CAMKES_CDL_TARGET "${CMAKE_CURRENT_BINARY_DIR}/${CAMKES_CDL_TARGET}.cdl")
    # Get an absolute reference to the ADL source
    get_absolute_source_or_binary(CAMKES_ADL_SOURCE "${adl}")
    # Declare a common CAMKES_FLAGS that we will need to give to every invocation of camkes
    set(CAMKES_FLAGS
        "--import-path=${CAMKES_TOOL_BUILTIN_DIR}"
        --platform seL4
        --architecture ${KernelSel4Arch}
        --default-priority ${CAmkESDefaultPriority}
        --default-affinity ${CAmkESDefaultAffinity}
        "--data-structure-cache-dir=${CMAKE_CURRENT_BINARY_DIR}/camkes_pickle"
    )
    # Build extra flags from the configuration
    # Each of these arguments is a CONDITION FLAG_IF_CONDITION_TRUE [FLAG_IF_CONDITION_FALSE]
    camkes_append_flags(
        "CAmkESVerbose;--debug"
        "CAmkESCompilationCache;--cache"
        "KernelIsMCS;--realtime"
        "CAmkESRPCLockElision;--frpc-lock-elision;--fno-rpc-lock-elision"
        "CAmkESSpecialiseSyscallStubs;--fspecialise-syscall-stubs;--fno-specialise-syscall-stubs"
        "CAmkESProvideTCBCaps;--fprovide-tcb-caps;--fno-provide-tcb-caps"
        "CAmkESSupportInit;--fsupport-init;--fno-support-init"
        "CAmkESLargeFramePromotion;--largeframe"
        "CAmkESDMALargeFramePromotion;--largeframe-dma"
        "CAmkESAllowForwardReferences;--allow-forward-references"
        "CAmkESFaultHandlers;--debug-fault-handlers"
        "CAmkESCPP;--cpp"
    )
    foreach(flag IN LISTS CAMKES_ROOT_CPP_FLAGS)
        if(NOT CAmkESCPP)
            message(FATAL_ERROR "Given CPP_FLAGS ${CAMKES_ROOT_CPP_FLAGS} but CAmkESCPP is disabled")
        endif()
        list(APPEND CAMKES_FLAGS "--cpp-flag=${flag}")
    endforeach()
    # Retrieve any extra import paths
    get_property(imports GLOBAL PROPERTY CAmkESExtraImportPaths)
    foreach(import IN LISTS imports)
        list(APPEND CAMKES_FLAGS "--import-path=${import}")
    endforeach()
    # Retrieve any templte paths
    get_property(templates GLOBAL PROPERTY CAmkESTemplatePaths)
    foreach(template IN LISTS templates)
        list(APPEND CAMKES_FLAGS --templates "${template}")
    endforeach()
    execute_process(
        # First delete the data structure cache directory as this is a new build
        COMMAND
            ${CMAKE_COMMAND} -E remove_directory "${CMAKE_CURRENT_BINARY_DIRECTOR}/camkes_pickle"
        COMMAND
            ${CMAKE_COMMAND} -E env ${CAMKES_TOOL_ENVIRONMENT} "${CAMKES_TOOL}"
                --file "${CAMKES_ADL_SOURCE}"
                --item camkes-gen.cmake
                --outfile "${CMAKE_CURRENT_BINARY_DIR}/camkes-gen.cmake"
                ${CAMKES_FLAGS}
        RESULT_VARIABLE camkes_gen_error
        OUTPUT_VARIABLE camkes_output
        ERROR_VARIABLE camkes_output
    )
    if (camkes_gen_error)
        message(FATAL_ERROR "Failed to generate camkes-gen.cmake: ${camkes_output}")
    endif()
    # We set a property to indicate that we have done execute_process (which happens during the
    # generation phase. This just allows us to do some debugging and detect cases where options
    # are changed *after* this point that would have affected the execute_process
    set_property(GLOBAL PROPERTY CAMKES_GEN_DONE TRUE)
    include(${CMAKE_CURRENT_BINARY_DIR}/camkes-gen.cmake)
endfunction(GenerateCAmkESRootserver)


# This is called by CAmkES components to declare information needed for the camkes-gen.cmake to
# actually build them
function(DeclareCAmkESComponent name)
    cmake_parse_arguments(PARSE_ARGV 1 CAMKES_COMPONENT
        "" # Option arguments
        "" # Single arguments
        "SOURCES;INCLUDES;C_FLAGS;LD_FLAGS;LIBS" # Multiple aguments
    )
    # Declare a target that we will set properties on
    add_custom_target(CAmkESComponent_${name})
    # Get absolute paths for the includes and sources
    set(includes "")
    set(sources "")
    foreach(inc IN LISTS CAMKES_COMPONENT_INCLUDES)
        get_absolute_source_or_binary(inc "${inc}")
        list(APPEND includes "${inc}")
    endforeach()
    foreach(file IN LISTS CAMKES_COMPONENT_SOURCES)
        get_absolute_source_or_binary(file "${file}")
        list(APPEND sources "${file}")
    endforeach()
    set_property(TARGET CAmkESComponent_${name} PROPERTY COMPONENT_INCLUDES "${includes}")
    set_property(TARGET CAmkESComponent_${name} PROPERTY COMPONENT_SOURCES "${sources}")
    set_property(TARGET CAmkESComponent_${name} PROPERTY COMPONENT_C_FLAGS "${CAMKES_COMPONENT_C_FLAGS}")
    set_property(TARGET CAmkESComponent_${name} PROPERTY COMPONENT_LD_FLAGS "${CAMKES_COMPONENT_LD_FLAGS}")
    set_property(TARGET CAmkESComponent_${name} PROPERTY COMPONENT_LIBS "${CAMKES_COMPONENT_LIBS}")
endfunction(DeclareCAmkESComponent)

# Helper function for adding additional import paths. Largely it exists to allow list
# files to give relative paths and have them automatically expanded to absolute paths
# We add the import paths to a property, instead of a target, since we need to use
# it in an `execute_process` above, which cannot take generator expressions
function(CAmkESAddImportPath)
    # Ensure we haven't generated the camkes-gen.cmake yet
    get_property(is_done GLOBAL PROPERTY CAMKES_GEN_DONE)
    if (is_done)
        message(FATAL_ERROR "Adding import path after camkes-gen.cmake has been generated")
    endif()
    foreach(arg IN LISTS ARGV)
        get_absolute_source_or_binary(arg "${arg}")
        set_property(GLOBAL APPEND PROPERTY CAmkESExtraImportPaths "${arg}")
    endforeach()
endfunction(CAmkESAddImportPath)
function(CAmkESAddTemplatesPath)
    # Ensure we haven't generated the camkes-gen.cmake yet
    get_property(is_done GLOBAL PROPERTY CAMKES_GEN_DONE)
    if (is_done)
        message(FATAL_ERROR "Adding templates path after camkes-gen.cmake has been generated")
    endif()
    foreach(arg IN LISTS ARGV)
        get_absolute_source_or_binary(arg "${arg}")
        set_property(GLOBAL APPEND PROPERTY CAmkESTemplatePaths "${arg}")
    endforeach()
endfunction(CAmkESAddTemplatesPath)
