# Export current ILA data after capture, without changing the trigger setup.
# In Vivado Hardware Manager: source this file, then export_pvm_capture path.csv.
proc export_pvm_capture {path} {
    set devices [get_hw_devices]
    if {[llength $devices] != 1} { error "Select exactly one PVM hardware target" }
    set ilas [get_hw_ilas -of_objects [lindex $devices 0]]
    if {[llength $ilas] != 1} { error "Expected one PVM ILA" }
    set capture [upload_hw_ila_data [lindex $ilas 0]]
    write_hw_ila_data -force -csv_file [file normalize $path] $capture
}
