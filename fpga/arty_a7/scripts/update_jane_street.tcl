# Source from the Vivado 2024.1 Tcl Console, then call pvm_board_update::apply.
namespace eval pvm_board_update {
    variable overlay [file dirname [file dirname [file normalize [info script]]]]
}

proc pvm_board_update::apply {project_file} {
    variable overlay
    set project_file [file normalize $project_file]
    set root [file dirname $project_file]
    if {![file isfile $project_file]} { error "Original project is missing: $project_file" }

    set python [auto_execok python]
    if {$python eq ""} { set python [auto_execok python3] }
    if {$python eq ""} { error "Python 3 is required to check the frozen PVM sources" }
    # Ignore the PYTHONHOME set by Vivado when running system Python.
    set python [concat $python {-E -B}]
    set scripts [file join $overlay scripts]
    if {![file isdirectory [file join $overlay freeze]]} {
        puts [exec {*}$python [file join $scripts extract_freeze.py]]
    }
    set rtl [split [string trim [exec {*}$python [file join $scripts verify_sources.py] --list]] "\n"]
    if {[llength $rtl] != 16} { error "Expected exactly 16 frozen PVM RTL files" }
    foreach name {pvm_arty_top.v uart_spi_bridge.v i2c_target_fixture.v} {
        lappend rtl [file join $overlay rtl $name]
    }
    set xdc [file join $overlay constr arty_a7_pvm.xdc]
    foreach path [concat $rtl [list $xdc]] {
        if {![file isfile $path]} { error "Required project input is missing: $path" }
    }

    if {[current_project -quiet] eq ""} { open_project $project_file }
    set project [current_project]
    if {[get_property NAME $project] ne "JANE_STREET" ||
        ![string equal -nocase [file normalize [get_property DIRECTORY $project]] $root]} {
        error "Save and close the current project, then apply the update to $project_file"
    }
    if {[get_property PART $project] ne "xc7a100tcsg324-1"} {
        error "Expected the Arty A7-100T part xc7a100tcsg324-1 in JANE_STREET"
    }

    set sources [get_filesets sources_1]
    set constraints [get_filesets constrs_1]
    set existing_xdc [get_files -quiet -of_objects $constraints]
    foreach file $existing_xdc {
        if {![string equal -nocase [file normalize [get_property NAME $file]] $xdc]} {
            error "Unexpected file in constrs_1: $file. Resolve the constraint overlap before updating."
        }
    }

    set ila [get_ips -quiet pvm_ila]
    set ila_config {CONFIG.C_NUM_OF_PROBES 12 CONFIG.C_DATA_DEPTH 131072
                    CONFIG.C_PROBE10_WIDTH 8 CONFIG.C_PROBE11_WIDTH 8
                    CONFIG.C_ADV_TRIGGER false}
    if {$ila ne ""} {
        foreach {key value} $ila_config {
            if {[get_property $key $ila] ne $value} {
                error "Existing pvm_ila has a different $key setting. Review that IP before updating."
            }
        }
    }

    set registered {}
    foreach file [get_files -quiet -of_objects $sources] {
        dict set registered [string tolower [file normalize [get_property NAME $file]]] 1
    }
    set missing {}
    foreach path $rtl {
        if {![dict exists $registered [string tolower [file normalize $path]]]} {
            lappend missing $path
        }
    }
    if {[llength $missing]} { add_files -fileset sources_1 -norecurse $missing }
    if {![llength $existing_xdc]} { add_files -fileset constrs_1 -norecurse $xdc }

    if {$ila eq ""} {
        create_ip -name ila -vendor xilinx.com -library ip -module_name pvm_ila
        set ila [get_ips pvm_ila]
        set_property -dict $ila_config $ila
    }
    generate_target all $ila
    set_property top pvm_arty_top $sources
    update_compile_order -fileset sources_1
    puts "PASS UPDATED_ORIGINAL_PROJECT $project_file"
}
