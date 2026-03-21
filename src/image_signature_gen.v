// =============================================================
// Module : image_signature_gen
// Purpose: Generate a 64-bit perceptual hash from an 8-bit
//          greyscale pixel stream.
//
// Algorithm (hardware pHash):
//   1. Accumulate pixels into 8x8 = 64 intensity cells
//   2. Compute per-cell mean
//   3. Compute global mean of 64 cell means
//   4. Bit[i] = 1 if cell_mean[i] >= global_mean, else 0
//
// Ports:
//   pixel_in    – 8-bit greyscale pixel value
//   pixel_valid – assert for exactly one cycle per pixel
//   image_done  – assert for one cycle AFTER the last pixel
//   signature   – 64-bit hash output
//   sig_valid   – pulses high for 1 cycle when signature ready
// =============================================================

module image_signature_gen #(
    parameter IMG_WIDTH  = 64,
    parameter IMG_HEIGHT = 64
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  pixel_in,
    input  wire        pixel_valid,
    input  wire        image_done,
    output reg  [63:0] signature,
    output reg         sig_valid
);

    // ── Constants ──────────────────────────────────────────
    localparam GRID           = 8;
    localparam CELLS          = 64;          // GRID*GRID
    localparam CELL_W         = IMG_WIDTH  / GRID;
    localparam CELL_H         = IMG_HEIGHT / GRID;
    localparam ACC_W          = 24;          // headroom for any image up to 256x256

    // ── Cell accumulators ───────────────────────────────────
    reg [ACC_W-1:0] cell_acc [0:63];
    reg [ACC_W-1:0] cell_cnt [0:63];

    // ── Pixel position ──────────────────────────────────────
    reg [15:0] px_col;
    reg [15:0] px_row;

    // ── FSM ────────────────────────────────────────────────
    localparam S_IDLE    = 2'd0;
    localparam S_ACCUM   = 2'd1;
    localparam S_COMPUTE = 2'd2;
    localparam S_DONE    = 2'd3;
    reg [1:0] state;

    // ── Compute-stage registers ─────────────────────────────
    reg [ACC_W-1:0]   cell_mean  [0:63];
    reg [ACC_W+6:0]   total_sum;
    reg [ACC_W-1:0]   global_mean;
    reg [6:0]         comp_idx;
    reg               phase;      // 0=calc means, 1=compare & build sig

    integer i;

    // ── Cell index from pixel position ──────────────────────
    wire [2:0] c_col = (px_col < CELL_W*1) ? 3'd0 :
                       (px_col < CELL_W*2) ? 3'd1 :
                       (px_col < CELL_W*3) ? 3'd2 :
                       (px_col < CELL_W*4) ? 3'd3 :
                       (px_col < CELL_W*5) ? 3'd4 :
                       (px_col < CELL_W*6) ? 3'd5 :
                       (px_col < CELL_W*7) ? 3'd6 : 3'd7;

    wire [2:0] c_row = (px_row < CELL_H*1) ? 3'd0 :
                       (px_row < CELL_H*2) ? 3'd1 :
                       (px_row < CELL_H*3) ? 3'd2 :
                       (px_row < CELL_H*4) ? 3'd3 :
                       (px_row < CELL_H*5) ? 3'd4 :
                       (px_row < CELL_H*6) ? 3'd5 :
                       (px_row < CELL_H*7) ? 3'd6 : 3'd7;

    wire [5:0] cell_idx = {c_row, c_col};

    // ── Main FSM ────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            px_col      <= 0;
            px_row      <= 0;
            sig_valid   <= 0;
            signature   <= 0;
            total_sum   <= 0;
            global_mean <= 0;
            comp_idx    <= 0;
            phase       <= 0;
            for (i = 0; i < CELLS; i = i + 1) begin
                cell_acc[i]  <= 0;
                cell_cnt[i]  <= 0;
                cell_mean[i] <= 0;
            end
        end else begin
            case (state)

                S_IDLE: begin
                    sig_valid <= 0;
                    if (pixel_valid) begin
                        for (i = 0; i < CELLS; i = i + 1) begin
                            cell_acc[i] <= 0;
                            cell_cnt[i] <= 0;
                        end
                        px_col <= 0;
                        px_row <= 0;
                        state  <= S_ACCUM;
                        cell_acc[0] <= pixel_in;
                        cell_cnt[0] <= 1;
                        px_col <= 1;
                    end
                end

                S_ACCUM: begin
                    if (pixel_valid) begin
                        cell_acc[cell_idx] <= cell_acc[cell_idx] + pixel_in;
                        cell_cnt[cell_idx] <= cell_cnt[cell_idx] + 1;
                        if (px_col == IMG_WIDTH - 1) begin
                            px_col <= 0;
                            px_row <= px_row + 1;
                        end else
                            px_col <= px_col + 1;
                    end
                    if (image_done) begin
                        state     <= S_COMPUTE;
                        comp_idx  <= 0;
                        phase     <= 0;
                        total_sum <= 0;
                    end
                end

                S_COMPUTE: begin
                    if (!phase) begin
                        // Phase 0: compute per-cell mean & accumulate total
                        cell_mean[comp_idx] <= (cell_cnt[comp_idx] != 0) ?
                            cell_acc[comp_idx] / cell_cnt[comp_idx] : 0;
                        total_sum <= total_sum +
                            ((cell_cnt[comp_idx] != 0) ?
                             cell_acc[comp_idx] / cell_cnt[comp_idx] : 0);
                        if (comp_idx == 63) begin
                            phase    <= 1;
                            comp_idx <= 0;
                            global_mean <= total_sum >> 6; // /64
                        end else
                            comp_idx <= comp_idx + 1;
                    end else begin
                        // Phase 1: compare cell mean to global mean
                        signature[comp_idx] <=
                            (cell_mean[comp_idx] >= global_mean) ? 1'b1 : 1'b0;
                        if (comp_idx == 63)
                            state <= S_DONE;
                        else
                            comp_idx <= comp_idx + 1;
                    end
                end

                S_DONE: begin
                    sig_valid <= 1;
                    state     <= S_IDLE;
                end

            endcase
        end
    end

endmodule
