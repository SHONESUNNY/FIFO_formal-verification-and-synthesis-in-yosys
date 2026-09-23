module formal_fifo_tb;

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 6;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    logic clk;
    logic rst_n;

    logic wr_en;
    logic rd_en;
    logic [DATA_WIDTH-1:0] din;

    logic [DATA_WIDTH-1:0] dout;
    logic full;
    logic empty;
    logic [ADDR_WIDTH-1:0] count ;

    // =========================================================
    // DUT
    // =========================================================

    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
        
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (wr_en),
        .rd_en (rd_en),
        .din   (din),
        .dout  (dout),
        .full  (full),
        .empty (empty),
        .count(count)
    );


    // =========================================================
    // FORMAL INPUTS
    // =========================================================

    // wr_en, rd_en and din are intentionally undriven.
    // The formal engine chooses their values.

    // Reset assumption
    always @(posedge clk) begin
        if ($initstate)
            assume (!rst_n);
        else
            assume (rst_n);
    end


    // =========================================================
    // ACCEPTED OPERATIONS
    // =========================================================

    wire write_accepted = wr_en && !full;
    wire read_accepted  = rd_en && !empty;


    // =========================================================
    // ASSERTIONS
    // =========================================================

    // FIFO cannot be both full and empty
    always @(posedge clk) begin
        if (rst_n)
            assert (!(full && empty));
    end


    // Empty iff count == 0
    always @(posedge clk) begin
        if (rst_n)
            assert (empty == (count == 0));
    end


    // Full iff count == DEPTH
    always @(posedge clk) begin
        if (rst_n)
            assert (full == (count == DEPTH));
    end
    
    //read only
always @(posedge clk) begin
    if (rst_n && $past(rst_n)) begin
        if ($past(read_accepted) && !$past(write_accepted)) begin
            assert (count == $past(count) - 1);
        end
    end
end
    
     //write only 
always @(posedge clk) begin
    if (rst_n && $past(rst_n)) begin
        if ($past(write_accepted) && !$past(read_accepted)) begin
            assert (count == $past(count) + 1);
        end
    end
end     

    // Count cannot exceed DEPTH
    always @(posedge clk) begin
        if (rst_n)
            assert (dut.count <= DEPTH);
    end

 /*     always @(posedge clk) begin

          if (rst_n && $past(rst_n)) begin

            if ($past(read_accepted) &&
                $past(write_accepted)) begin

                assert (
                    dut.count == $past(dut.count)
                );                 

            end
        end
    end
                */

endmodule
