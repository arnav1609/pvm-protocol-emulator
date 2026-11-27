# Vivado 2024.1 entry point. Source with no arguments to create the project.
# In batch mode, add -tclargs build C:/path/to/scratch to implement the project.
# Use -tclargs verify C:/path/to/scratch to check an existing routed project.
set script_dir [file dirname [file normalize [info script]]]
set overlay [file dirname $script_dir]
set part xc7a100tcsg324-1
set project_name JaneStreet_Vivado_Run
set argv_local [expr {[info exists argv] ? $argv : {}}]
set mode [expr {[llength $argv_local] ? [lindex $argv_local 0] : "create"}]
if {$mode ni {create build verify} || [llength $argv_local] > 2} {
    error "Usage: create_project.tcl ?create|build|verify? ?output-directory?"
}
set output [file join $overlay vivado]
if {[llength $argv_local] == 2} {
    set output [lindex $argv_local 1]
}
set output [file normalize $output]
set project_file [file join $output ${project_name}.xpr]

proc check_implementation {output} {
    set impl [get_runs impl_1]
    if {[get_property PROGRESS $impl] ne "100%"} {
        error "FPGA implementation did not complete: [get_property STATUS $impl]"
    }
    set run_dir [get_property DIRECTORY $impl]
    set bitstream [file join $run_dir pvm_arty_top.bit]
    if {![file isfile $bitstream]} { error "FPGA bitstream missing" }
    open_run impl_1
    report_utilization -file [file join $output utilization_artix7.rpt]
    report_timing_summary -report_unconstrained -check_timing_verbose -file [file join $output timing_artix7.rpt]
    report_clocks -file [file join $output clocks_artix7.rpt]
    report_drc -file [file join $output drc_artix7.rpt]
    foreach period {10.000 20.000} {
        set found 0
        foreach clk [get_clocks] {
            if {abs([get_property PERIOD $clk] - $period) < 0.001} {set found 1}
        }
        if {!$found} {error "Expected a clock with period $period ns"}
    }
    foreach {name delay} {WNS max WHS min} {
        set paths [get_timing_paths -max_paths 1 -delay_type $delay]
        if {[llength $paths] != 1} { error "No $name timing path" }
        set slack [get_property SLACK $paths]
        if {![regexp {^-?[0-9]+(\.[0-9]+)?$} $slack] || $slack < 0} {
            error "$name fails: $slack"
        }
        puts "$name $slack ns"
    }
    if {[llength [get_drc_violations -quiet {UCIO* NSTD*}]]} {
        error "FPGA port constraint DRC failed"
    }
    set probes [file join $run_dir debug_nets.ltx]
    if {![file isfile $probes]} { write_debug_probes -force $probes }
    if {![file isfile $probes]} { error "FPGA debug probes file missing" }
    puts "PASS FPGA_SCRATCH_BUILD $bitstream"
}

if {$mode eq "verify"} {
    open_project $project_file
    check_implementation $output
    return
}
if {$::tcl_platform(platform) eq "windows"} {
    set debug_dir [file join $output ${project_name}.runs impl_1 .Xil "Vivado-00000000-[info hostname]"]
    if {[string length $debug_dir] > 146} {
        error "Vivado debug hub needs a shorter Windows build directory. Choose a short output path with -tclargs $mode <directory>."
    }
}
if {[file exists $project_file]} {
    error "Project already exists at $output. Choose a fresh output directory."
}

set python [auto_execok python]
if {$python eq ""} { set python [auto_execok python3] }
if {$python eq ""} { error "Python 3 is required for the frozen-source preflight" }
if {[info exists env(PVM_PYTHON)] && $env(PVM_PYTHON) ne ""} {
    set python [list $env(PVM_PYTHON)]
}
# Vivado sets PYTHONHOME to its bundled Python, which can poison system Python.
set python [concat $python {-E -B}]
if {![file isdirectory [file join $overlay freeze]]} {
    puts [exec {*}$python [file join $script_dir extract_freeze.py]]
}
set source_output [exec {*}$python [file join $script_dir verify_sources.py] --list]
set sources [split [string trim $source_output] "\n"]
if {[llength $sources] != 16} { error "Expected 16 ordered frozen source files" }
puts "Frozen PVM at b33a9227ac187f791a3733b94ac4e32879b10414:"
foreach source $sources { puts "  $source" }

create_project $project_name $output -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse $sources
foreach source {pvm_arty_top.v uart_spi_bridge.v i2c_target_fixture.v} {
    add_files -norecurse [file join $overlay rtl $source]
}
add_files -fileset constrs_1 -norecurse [file join $overlay constr arty_a7_pvm.xdc]
set_property top pvm_arty_top [get_filesets sources_1]

# Persist an ILA that spans both packets of the 29-word DMX512 demo.
create_ip -name ila -vendor xilinx.com -library ip -module_name pvm_ila
set ila [get_ips pvm_ila]
set_property -dict [list CONFIG.C_NUM_OF_PROBES {12} CONFIG.C_DATA_DEPTH {131072} \
    CONFIG.C_PROBE10_WIDTH {8} CONFIG.C_PROBE11_WIDTH {8} \
    CONFIG.C_ADV_TRIGGER {false}] $ila
generate_target all $ila
update_compile_order -fileset sources_1
puts "PASS FPGA_PROJECT_CREATED $project_file"

if {$mode eq "build"} {
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    check_implementation $output
}
