open_project ./vivado_prj/msximus_zynq.xpr
open_run synth_1
report_clocks -file ./clocks_synth.rpt
report_clock_interaction -file ./clock_interaction_synth.rpt
puts CLOCKS_OK
exit
