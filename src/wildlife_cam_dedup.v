// =============================================================
// Module : wildlife_cam_dedup  (TOP LEVEL)
// Purpose: Instantiates two image_signature_gen modules and
//          one signature_comparator.
//
// Flow:
//   1. Stream image A pixels → image_done_a → sig_a ready
//   2. Stream image B pixels → image_done_b → sig_b ready
//   3. Assert compare_en → is_duplicate result 1 cycle later
// =============================================================

module wildlife_cam_dedup #(
    parameter IMG_WIDTH  = 64,
    parameter IMG_HEIGHT = 64,
    parameter THRESHOLD  = 10
)(
    input  wire        clk,
    input  wire        rst_n,

    // Image A
    input  wire [7:0]  pixel_in_a,
    input  wire        pixel_valid_a,
    input  wire        image_done_a,

    // Image B
    input  wire [7:0]  pixel_in_b,
    input  wire        pixel_valid_b,
    input  wire        image_done_b,

    // Control
    input  wire        compare_en,

    // Outputs
    output wire [63:0] sig_a,
    output wire [63:0] sig_b,
    output wire        sig_a_valid,
    output wire        sig_b_valid,
    output wire [6:0]  hamming_dist,
    output wire        is_duplicate,
    output wire        result_valid
);

    image_signature_gen #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_gen_a (
        .clk        (clk),
        .rst_n      (rst_n),
        .pixel_in   (pixel_in_a),
        .pixel_valid(pixel_valid_a),
        .image_done (image_done_a),
        .signature  (sig_a),
        .sig_valid  (sig_a_valid)
    );

    image_signature_gen #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_gen_b (
        .clk        (clk),
        .rst_n      (rst_n),
        .pixel_in   (pixel_in_b),
        .pixel_valid(pixel_valid_b),
        .image_done (image_done_b),
        .signature  (sig_b),
        .sig_valid  (sig_b_valid)
    );

    signature_comparator #(
        .THRESHOLD(THRESHOLD)
    ) u_cmp (
        .clk         (clk),
        .rst_n       (rst_n),
        .sig_a       (sig_a),
        .sig_b       (sig_b),
        .compare_en  (compare_en),
        .hamming_dist(hamming_dist),
        .is_duplicate(is_duplicate),
        .result_valid(result_valid)
    );

endmodule
