# Run from the Vivado Hardware Manager that programmed the J3 PVM image.
namespace eval pvm_ila_run {
    variable overlay [file dirname [file dirname [file normalize [info script]]]]
    variable sequence {
        {reset              reset.csv       {9 F}}
        {{uart_tx 1}        uart.csv        {0 F}}
        {{spi_mode0 1}      spi.csv         {1 R}}
        {{i2c_write 1}      i2c.csv         {3 F 4 1}}
        {{dmx512_tx 1}      dmx512_run1.csv {0 F}}
        {{dmx512_tx 2}      dmx512_run2.csv {0 F}}
    }
}

proc pvm_ila_run::expect {host expected hostLog} {
    set deadline [expr {[clock milliseconds] + 60000}]
    while {[gets $host line] < 0} {
        if {[eof $host]} {
            set message "USB host exited while waiting for $expected."
            if {[file isfile $hostLog]} {
                set log [open $hostLog r]
                try {
                    set lines [split [string trimright [read $log]] "\n"]
                } finally {
                    close $log
                }
                set last [lindex $lines end]
                if {$last ne ""} { append message " $last" }
            }
            error "$message See $hostLog"
        }
        if {[clock milliseconds] >= $deadline} { error "Timed out waiting for $expected. See $hostLog" }
        after 25
    }
    if {$line ne $expected} { error "Expected '$expected', received '$line'. See $hostLog" }
}

proc pvm_ila_run::capture {ila probes trigger host path} {
    reset_hw_ila $ila
    # A Basic-only core exposes its mode as read-only. Reset provides all of these defaults.
    foreach {key expected} {CONTROL.TRIGGER_MODE BASIC_ONLY CONTROL.TRIGGER_CONDITION AND
                            CONTROL.CAPTURE_MODE ALWAYS CONTROL.WINDOW_COUNT 1
                            CONTROL.DATA_DEPTH 131072} {
        set value [get_property $key $ila]
        if {$value ne $expected} { error "The PVM ILA returned $key=$value after reset. Expected $expected." }
    }
    set_property CONTROL.TRIGGER_POSITION 1024 $ila
    foreach {index value} $trigger {
        set_property TRIGGER_COMPARE_VALUE "eq1'b$value" [dict get $probes $index]
    }
    run_hw_ila $ila
    # Let the ILA fill its 1024 pre-trigger samples before the host sends ENABLE.
    after 10
    puts $host GO
    flush $host
    wait_on_hw_ila -timeout 0.25 $ila
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file $path $data
    if {![file isfile $path] || [file size $path] == 0} { error "ILA did not write $path" }
}

proc pvm_ila_run::all {{port COM3}} {
    variable overlay
    variable sequence
    if {![regexp -nocase {^COM[1-9][0-9]*$} $port]} { error "Specify a Windows COM port, for example COM3" }
    set devices [get_hw_devices -quiet xc7a100t*]
    if {[llength $devices] != 1} {
        error "Connect and program one Arty A7-100T in this Vivado Hardware Manager first."
    }
    set ilas [get_hw_ilas -quiet -of_objects [lindex $devices 0]]
    if {[llength $ilas] != 1} { error "The programmed Arty should show one ILA. Load its matching debug_nets.ltx first." }
    set ila [lindex $ilas 0]
    if {[get_property STATIC.MAX_DATA_DEPTH $ila] != 131072} {
        error "The PVM image expects an ILA with 131072 samples per capture."
    }
    set probes {}
    foreach probe [get_hw_probes -of_objects $ila] {
        set index [get_property PROBE_PORT $probe]
        if {[dict exists $probes $index]} { error "Duplicate probe on port $index" }
        dict set probes $index $probe
    }
    if {[lsort -integer [dict keys $probes]] ne {0 1 2 3 4 5 6 7 8 9 10 11}} {
        error "Expected all 12 PVM ILA ports from the matching probes file."
    }
    foreach {index width} {0 1 1 1 3 1 4 1 9 1 10 8 11 8} {
        if {[get_property PROBE_PORT_BIT_COUNT [dict get $probes $index]] != $width} {
            error "Unexpected width on PVM ILA probe $index"
        }
    }

    set python [auto_execok python]
    if {$python eq ""} { error "Python with pySerial is required" }
    set python [concat $python {-E -B -X utf8}]
    set runner [file join $overlay host run_demos.py]
    set compare [file join $overlay scripts compare_capture.py]
    set folder [file join $overlay board_results "auto_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[clock milliseconds]"]
    file mkdir $folder
    puts "PVM results folder: $folder"
    set hostLog [file join $folder host.log]
    set command [concat [list |] $python [list $runner --port $port --ila-sync \
        --output [file join $folder readback.jsonl] 2> $hostLog]]
    set host [open $command r+]
    fconfigure $host -blocking 0 -buffering line -encoding utf-8
    set completed 0
    try {
        foreach item $sequence {
            lassign $item label csv trigger
            expect $host "READY $label" $hostLog
            puts "Capturing $label"
            capture $ila $probes $trigger $host [file join $folder $csv]
            expect $host "DONE $label" $hostLog
        }
        set completed 1
    } on error {message options} {
        catch {reset_hw_ila $ila}
        catch {puts $host STOP; flush $host}
        set deadline [expr {[clock milliseconds] + 3000}]
        while {![eof $host] && [clock milliseconds] < $deadline} {
            read $host
            after 25
        }
        return -options $options $message
    } finally {
        if {$completed || [eof $host]} { fconfigure $host -blocking 1 }
        if {[catch {close $host} message] && $completed} {
            error "USB host failed to finish. See $hostLog. $message"
        }
    }

    set comparisons [file join $folder comparisons.log]
    set failures {}
    foreach check {
        {reset {reset.csv} {}}
        {uart {uart.csv} {}}
        {spi {spi.csv} {}}
        {i2c {i2c.csv} {--i2c-target board-fixture}}
        {dmx512 {dmx512_run1.csv dmx512_run2.csv} {}}
    } {
        lassign $check protocol files args
        set paths {}
        foreach name $files { lappend paths [file join $folder $name] }
        if {[catch {exec {*}$python $compare $protocol {*}$paths {*}$args >> $comparisons 2>@1}]} {
            lappend failures $protocol
        }
    }
    if {[llength $failures]} { error "Capture comparison failed for [join $failures {, }]. See $comparisons" }
    puts "PASS reset, five readbacks and five protocol captures. Results: $folder"
    return $folder
}
