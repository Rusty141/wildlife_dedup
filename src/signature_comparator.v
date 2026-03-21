// =============================================================
// Module : signature_comparator
// Purpose: Compute Hamming distance between two 64-bit image
//          signatures and flag as duplicate if distance <=
//          configurable THRESHOLD.
// =============================================================

module signature_comparator #(
    parameter THRESHOLD = 10
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [63:0] sig_a,
    input  wire [63:0] sig_b,
    input  wire        compare_en,
    output reg  [6:0]  hamming_dist,
    output reg         is_duplicate,
    output reg         result_valid
);

    // ── Combinational popcount (adder tree) ─────────────────
    wire [63:0] xr = sig_a ^ sig_b;

    // Stage 0: 32 x 2-bit
    wire [1:0] s0[0:31];
    genvar g;
    generate
        for (g=0;g<32;g=g+1) begin:S0
            assign s0[g] = {1'b0,xr[g*2+1]} + {1'b0,xr[g*2]};
        end
    endgenerate

    // Stage 1: 16 x 3-bit
    wire [2:0] s1[0:15];
    generate
        for (g=0;g<16;g=g+1) begin:S1
            assign s1[g] = {1'b0,s0[g*2+1]} + {1'b0,s0[g*2]};
        end
    endgenerate

    // Stage 2: 8 x 4-bit
    wire [3:0] s2[0:7];
    generate
        for (g=0;g<8;g=g+1) begin:S2
            assign s2[g] = {1'b0,s1[g*2+1]} + {1'b0,s1[g*2]};
        end
    endgenerate

    // Stage 3: 4 x 5-bit
    wire [4:0] s3[0:3];
    generate
        for (g=0;g<4;g=g+1) begin:S3
            assign s3[g] = {1'b0,s2[g*2+1]} + {1'b0,s2[g*2]};
        end
    endgenerate

    // Stage 4: 2 x 6-bit
    wire [5:0] s4_0 = {1'b0,s3[1]} + {1'b0,s3[0]};
    wire [5:0] s4_1 = {1'b0,s3[3]} + {1'b0,s3[2]};

    // Stage 5: final 7-bit count
    wire [6:0] popcount = {1'b0,s4_1} + {1'b0,s4_0};

    // ── Register on compare_en ───────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hamming_dist <= 0;
            is_duplicate <= 0;
            result_valid <= 0;
        end else begin
            result_valid <= 0;
            if (compare_en) begin
                hamming_dist <= popcount;
                is_duplicate <= (popcount <= THRESHOLD) ? 1'b1 : 1'b0;
                result_valid <= 1;
            end
        end
    end

endmodule
