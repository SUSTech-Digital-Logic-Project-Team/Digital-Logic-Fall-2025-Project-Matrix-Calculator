# Vivado TCL script for timing optimization
# Run this AFTER synthesis but BEFORE place and route

# Enable aggressive timing-driven placement and routing
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE WLDriven [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

# Enable optimization
set_property STEPS.OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE NullSynthesis [get_runs impl_1]

# Log message
puts "Timing optimization directives applied"
