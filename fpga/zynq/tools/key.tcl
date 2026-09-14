# key.tcl — "manos" del MSXimus en la ZYNQ MINI desde XSDB: pulsa teclas a traves
# del buzon de la DDR (zynq/dbg_mailbox_axi.v, HP2). El PL lee el bitmap HID de
# 128 bits en MBOX cada ~1 ms y lo OR-ea con el teclado USB (top_zynq: keyboard).
#
# Uso:  xsdb.bat tools/key.tcl RETURN            (una tecla)
#       xsdb.bat tools/key.tcl ESC F11 DOWN RETURN (secuencia de teclas)
#       xsdb.bat tools/key.tcl -type {print "hola"} RETURN   (texto literal + teclas)
# Teclas: RETURN ESC SPACE TAB BS UP DOWN LEFT RIGHT HOME INS DEL F1..F12 KANA
#         SHIFT+x (p.ej. SHIFT+2). Letras y digitos sueltos se aceptan como tecla.
# El bitmap se indexa por usage HID (usb_kbd_decode.v): modificadores en 104+bit
# (LCtrl=104, LShift=105, LAlt=106=CODE/KANA).
set MBOX     0x1FF00000
set HOLD_MS  90        ;# tiempo pulsada (el MSX escanea a 60 Hz)
set GAP_MS   60        ;# tiempo entre teclas (para repetir la misma letra)

array set KEY {
    RETURN 40 ENTER 40 ESC 41 BS 42 BACKSPACE 42 TAB 43 SPACE 44
    MINUS 45 EQUAL 46 LBRACKET 47 RBRACKET 48 BACKSLASH 49 SEMICOLON 51 QUOTE 52
    GRAVE 53 COMMA 54 DOT 55 SLASH 56 CAPS 57
    F1 58 F2 59 F3 60 F4 61 F5 62 F6 63 F7 64 F8 65 F9 66 F10 67 F11 68 F12 69
    INS 73 HOME 74 PGUP 75 DEL 76 END 77 PGDN 78 RIGHT 79 LEFT 80 DOWN 81 UP 82
    CTRL 104 SHIFT 105 KANA 106 CODE 106 GRAPH 107
}
# caracteres -> {usage shift}
proc char2hid {ch} {
    if {[string is lower $ch] && [string is alpha $ch]} { return [list [expr {[scan $ch %c] - 97 + 4}] 0] }
    if {[string is upper $ch] && [string is alpha $ch]} { return [list [expr {[scan $ch %c] - 65 + 4}] 1] }
    if {$ch eq "0"} { return {39 0} }
    if {[string is digit $ch]} { return [list [expr {[scan $ch %c] - 49 + 30}] 0] }
    switch -exact -- $ch {
        " " { return {44 0} }  "-" { return {45 0} }  "=" { return {46 0} }  "\[" { return {47 0} }
        "\]" { return {48 0} } ";" { return {51 0} }  "'" { return {52 0} }  "," { return {54 0} }
        "." { return {55 0} }  "/" { return {56 0} }  "`" { return {53 0} }
        "!" { return {30 1} }  "@" { return {31 1} }  "#" { return {32 1} }  "\$" { return {33 1} }
        "%" { return {34 1} }  "^" { return {35 1} }  "&" { return {36 1} }  "*" { return {37 1} }
        "(" { return {38 1} }  ")" { return {39 1} }  "_" { return {45 1} }  "+" { return {46 1} }
        ":" { return {51 1} }  "\"" { return {52 1} } "<" { return {54 1} }  ">" { return {55 1} }
        "?" { return {56 1} }  "~" { return {53 1} }  "\\" { return {49 0} } "|" { return {49 1} }
    }
    error "caracter sin mapa: '$ch'"
}
proc words_of {codes} {
    set w {0 0 0 0}
    foreach c $codes {
        set i [expr {$c >> 5}]
        lset w $i [expr {[lindex $w $i] | (1 << ($c & 31))}]
    }
    return $w
}
proc press {codes} {
    mwr $::MBOX [words_of $codes] 4
    after $::HOLD_MS
    mwr $::MBOX {0 0 0 0} 4
    after $::GAP_MS
}
proc keyname2codes {name} {
    set codes {}
    foreach part [split [string toupper $name] +] {
        if {[info exists ::KEY($part)]} { lappend codes $::KEY($part) } \
        elseif {[string length $part] == 1} { lappend codes [lindex [char2hid [string tolower $part]] 0] } \
        else { error "tecla desconocida: $part" }
    }
    return $codes
}
proc type_text {txt} {
    foreach ch [split $txt ""] {
        lassign [char2hid $ch] code sh
        press [expr {$sh ? [list $code 105] : [list $code]}]
    }
}

connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set i 0
while {$i < $argc} {
    set a [lindex $argv $i]
    if {$a eq "-type"} { incr i; type_text [lindex $argv $i]; puts "typed: [lindex $argv $i]" } \
    elseif {$a eq "-hold"} { incr i; set HOLD_MS [lindex $argv $i] } \
    else { press [keyname2codes $a]; puts "key: $a" }
    incr i
}
exit
