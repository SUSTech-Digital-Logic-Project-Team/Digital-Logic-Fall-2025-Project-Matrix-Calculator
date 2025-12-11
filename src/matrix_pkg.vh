// ========================================
// Matrix calculator common parameters and constants package
// RESTRUCTURED VERSION - Optimized for BRAM usage
// ========================================

`ifndef MATRIX_PKG_VH
`define MATRIX_PKG_VH

// System parameters
`define CLK_FREQ          100_000_000
`define BAUD_RATE         115200
`define MAX_POSSIBLE_DIM  16
`define MAX_STORAGE_MATRICES 16
`define MAX_ELEMENTS      4096
`define BRAM_ADDR_WIDTH   12          // 2^12 = 4096
`define DEFAULT_MAX_DIM   5
`define DEFAULT_MAX_VALUE 9
`define DEFAULT_MATRICES_PER_SIZE 5
`define DEFAULT_ERROR_SECONDS 10
`define MIN_ERROR_SECONDS 5
`define MAX_ERROR_SECONDS 15
`define ELEMENT_WIDTH     8

// Main state machine states
`define MAIN_MENU    3'd0
`define MODE_INPUT   3'd1
`define MODE_GENERATE 3'd2
`define MODE_DISPLAY 3'd3
`define MODE_COMPUTE 3'd4
`define MODE_SETTING 3'd5

// Error codes
`define ERR_NONE         4'd0
`define ERR_DIM_RANGE    4'd1
`define ERR_VALUE_RANGE  4'd2
`define ERR_NO_SPACE     4'd3
`define ERR_INVALID_OP   4'd4
`define ERR_DIM_MISMATCH 4'd5

// Operation types
`define OP_TRANSPOSE  4'd0
`define OP_ADD        4'd1
`define OP_SCALAR_MUL 4'd2
`define OP_MATRIX_MUL 4'd3
`define OP_CONVOLUTION 4'd4

`endif // MATRIX_PKG_VH
