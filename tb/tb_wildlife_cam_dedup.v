// =============================================================
// Testbench : tb_wildlife_cam_dedup
// Test cases:
//   TC1 – Identical images              → DUPLICATE
//   TC2 – Slightly brighter image (+5)  → DUPLICATE
//   TC3 – Gradient vs checkerboard      → NOT DUPLICATE
//   TC4 – Gradient vs inverted          → NOT DUPLICATE
//   TC5 – Same uniform image            → DUPLICATE
// =============================================================

`timescale 1ns / 1ps

module tb_wildlife_cam_dedup;

    // ── Parameters ──────────────────────────────────────────
    localparam IMG_W  = 64;
    localparam IMG_H  = 64;
    localparam N_PIX  = IMG_W * IMG_H;   // 4096
    localparam THRESH = 10;
    localparam HALF   = 5;               // 10 ns clock

    // ── DUT ports ───────────────────────────────────────────
    reg        clk, rst_n;
    reg [7:0]  pixel_in_a;
    reg        pixel_valid_a, image_done_a;
    reg [7:0]  pixel_in_b;
    reg        pixel_valid_b, image_done_b;
    reg        compare_en;

    wire [63:0] sig_a, sig_b;
    wire        sig_a_valid, sig_b_valid;
    wire [6:0]  hamming_dist;
    wire        is_duplicate, result_valid;

    // ── Image buffers ────────────────────────────────────────
    reg [7:0] img_A [0:N_PIX-1];
    reg [7:0] img_B [0:N_PIX-1];

    // ── Counters ─────────────────────────────────────────────
    integer pass_cnt, fail_cnt, tc, k, r, c;

    // ── DUT ──────────────────────────────────────────────────
    wildlife_cam_dedup #(
        .IMG_WIDTH (IMG_W),
        .IMG_HEIGHT(IMG_H),
        .THRESHOLD (THRESH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .pixel_in_a   (pixel_in_a),
        .pixel_valid_a(pixel_valid_a),
        .image_done_a (image_done_a),
        .pixel_in_b   (pixel_in_b),
        .pixel_valid_b(pixel_valid_b),
        .image_done_b (image_done_b),
        .compare_en   (compare_en),
        .sig_a        (sig_a),
        .sig_b        (sig_b),
        .sig_a_valid  (sig_a_valid),
        .sig_b_valid  (sig_b_valid),
        .hamming_dist (hamming_dist),
        .is_duplicate (is_duplicate),
        .result_valid (result_valid)
    );

    // ── Clock ────────────────────────────────────────────────
    initial clk = 0;
    always  #HALF clk = ~clk;

    // ── Reset ────────────────────────────────────────────────
    task do_reset;
    begin
        rst_n         <= 0;
        pixel_valid_a <= 0; image_done_a <= 0; pixel_in_a <= 0;
        pixel_valid_b <= 0; image_done_b <= 0; pixel_in_b <= 0;
        compare_en    <= 0;
        repeat(6) @(posedge clk); #1;
        rst_n <= 1;
        repeat(2) @(posedge clk); #1;
    end
    endtask

    // ── Stream one image ─────────────────────────────────────
    // ch=0 → channel A,  ch=1 → channel B
    task stream_image;
        input integer ch;
        integer j;
    begin
        for (j = 0; j < N_PIX; j = j + 1) begin
            @(posedge clk); #1;
            if (ch == 0) begin
                pixel_in_a    <= img_A[j];
                pixel_valid_a <= 1;
            end else begin
                pixel_in_b    <= img_B[j];
                pixel_valid_b <= 1;
            end
        end
        @(posedge clk); #1;
        if (ch == 0) begin
            pixel_valid_a <= 0;
            image_done_a  <= 1;
        end else begin
            pixel_valid_b <= 0;
            image_done_b  <= 1;
        end
        @(posedge clk); #1;
        image_done_a <= 0;
        image_done_b <= 0;
    end
    endtask

    // ── Wait for both sigs then compare ──────────────────────
    task run_compare;
        input integer expect_dup;
        integer got_a, got_b, timeout;
    begin
        got_a = 0; got_b = 0; timeout = 0;
        while ((!got_a || !got_b) && timeout < 10000) begin
            @(posedge clk);
            if (sig_a_valid) got_a = 1;
            if (sig_b_valid) got_b = 1;
            timeout = timeout + 1;
        end
        repeat(2) @(posedge clk); #1;
        compare_en <= 1;
        @(posedge clk); #1;
        compare_en <= 0;
        // wait for result_valid
        timeout = 0;
        while (!result_valid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(posedge clk);
        $display("  TC%0d | hamming=%0d | is_dup=%0b | expected=%0b | sig_a=%h",
                 tc, hamming_dist, is_duplicate, expect_dup, sig_a);
        if (is_duplicate === expect_dup[0]) begin
            $display("        --> PASS");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("        --> FAIL ***");
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    // ── Image helpers ─────────────────────────────────────────
    task make_gradient_a;
    begin
        for (r=0; r<IMG_H; r=r+1)
            for (c=0; c<IMG_W; c=c+1)
                img_A[r*IMG_W+c] = (r * 255) / (IMG_H-1);
    end
    endtask

    task copy_a_to_b; begin
        for (k=0;k<N_PIX;k=k+1) img_B[k] = img_A[k];
    end endtask

    task brighten_b;
        input [7:0] off;
    begin
        for (k=0;k<N_PIX;k=k+1)
            img_B[k] = (img_A[k]+off > 255) ? 8'd255 : img_A[k]+off;
    end
    endtask

    task make_checkerboard_b; begin
        for (r=0;r<IMG_H;r=r+1)
            for (c=0;c<IMG_W;c=c+1)
                img_B[r*IMG_W+c] = ((r/8 + c/8)%2 == 0) ? 8'd255 : 8'd0;
    end endtask

    task make_inverted_b; begin
        for (k=0;k<N_PIX;k=k+1) img_B[k] = 8'd255 - img_A[k];
    end endtask

    task make_uniform;
        input [7:0] val;
        input integer dest; // 0=A,1=B
    begin
        for (k=0;k<N_PIX;k=k+1)
            if (dest==0) img_A[k]=val; else img_B[k]=val;
    end
    endtask

    // ── MAIN TEST ─────────────────────────────────────────────
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        $dumpfile("sim_output.vcd");
        $dumpvars(0, tb_wildlife_cam_dedup);

        $display("=====================================================");
        $display("  Wildlife Cam Dedup Testbench  (%0dx%0d, thresh=%0d)",
                 IMG_W, IMG_H, THRESH);
        $display("=====================================================");

        // -- TC1: Identical ──────────────────────────────────
        tc = 1;
        $display("\n[TC1] Identical images  =>  expect DUPLICATE");
        do_reset;
        make_gradient_a; copy_a_to_b;
        stream_image(0); stream_image(1);
        run_compare(1);

        // -- TC2: Slightly brighter ──────────────────────────
        tc = 2;
        $display("\n[TC2] Brighter by +5  =>  expect DUPLICATE");
        do_reset;
        make_gradient_a; brighten_b(8'd5);
        stream_image(0); stream_image(1);
        run_compare(1);

        // -- TC3: Gradient vs checkerboard ───────────────────
        tc = 3;
        $display("\n[TC3] Gradient vs Checkerboard  =>  expect NOT DUPLICATE");
        do_reset;
        make_gradient_a; make_checkerboard_b;
        stream_image(0); stream_image(1);
        run_compare(0);

        // -- TC4: Gradient vs inverted ───────────────────────
        tc = 4;
        $display("\n[TC4] Gradient vs Inverted  =>  expect NOT DUPLICATE");
        do_reset;
        make_gradient_a; make_inverted_b;
        stream_image(0); stream_image(1);
        run_compare(0);

        // -- TC5: Identical uniform ──────────────────────────
        tc = 5;
        $display("\n[TC5] Uniform 128 vs Uniform 128  =>  expect DUPLICATE");
        do_reset;
        make_uniform(8'd128, 0); make_uniform(8'd128, 1);
        stream_image(0); stream_image(1);
        run_compare(1);

        $display("\n=====================================================");
        $display("  RESULTS:  %0d PASSED   %0d FAILED", pass_cnt, fail_cnt);
        $display("=====================================================\n");
        #200;
        $finish;
    end

    initial begin
        #50_000_000;
        $display("WATCHDOG: simulation timeout");
        $finish;
    end

endmodule
