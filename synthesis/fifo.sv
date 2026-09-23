`timescale 1ns / 1ps

module fifo#(
    parameter DATA_WIDTH = 8 ,
    parameter DEPTH = 6,
    parameter ADDR_WIDTH = $clog2(DEPTH)
    )(
    input clk , rst_n , wr_en , rd_en ,
    input logic [DATA_WIDTH -1 :0] din ,
    output logic [DATA_WIDTH-1:0] dout,
    output logic  full, empty ,
    output logic [ADDR_WIDTH:0] count
    
    );
    
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_WIDTH-1:0] wr_ptr;
    logic [ADDR_WIDTH-1:0] rd_ptr;
    logic [ADDR_WIDTH:0] count;
    
    always @(posedge clk or negedge rst_n)begin 
    
    if(!rst_n) wr_ptr <='0 ;
       else if(wr_en && !full)begin
         mem[wr_ptr] <= din;
         wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1 ;  
      end
  end  
 
   // Read Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            dout  <= '0;
        end
        else if (rd_en && !empty) begin
            dout <= mem[rd_ptr];
            rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1;
        end
   end

    // Count Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= '0;
        else begin
        
            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1; // Write only
                2'b01: count <= count - 1; // Read only
                default: count <= count;   // No change or simultaneous
            endcase
        end
    end

    assign full  = (count == DEPTH);
    assign empty = (count == 0);

endmodule
