/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        output_port_lookup.v
 *
 *  Library:
 *        hw/contrib/pcores/packet_capture_v1_00_a
 *
 *  Module:
 *        packet_duplic
 *
 *  Author:
 *        Lucas Brasilino
 *
 *  Description:
 *        Does packet duplication
 *
 *  Copyright notice:
 *        Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
 *                                 Junior University
 *
 *  Licence:
 *        This file is part of the NetFPGA 10G development base package.
 *
 *        This file is free code: you can redistribute it and/or modify it under
 *        the terms of the GNU Lesser General Public License version 2.1 as
 *        published by the Free Software Foundation.
 *
 *        This package is distributed in the hope that it will be useful, but
 *        WITHOUT ANY WARRANTY; without even the implied warranty of
 *        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *        Lesser General Public License for more details.
 *
 *        You should have received a copy of the GNU Lesser General Public
 *        License along with the NetFPGA source package.  If not, see
 *        http://www.gnu.org/licenses/.
 *
 */

module packet_duplic
#(
    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH=256,
    parameter C_S_AXIS_DATA_WIDTH=256,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXI_DATA_WIDTH=32,
    // Register parameters
    parameter NUM_RW_REGS = 0,
    parameter NUM_WO_REGS = 0,
    parameter NUM_RO_REGS = 0
)
(
    // Global Ports
    input axi_aclk,
    input axi_aresetn,

    // Master Stream Port 0
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata_0,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tstrb_0,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser_0,
    output reg                                 m_axis_tvalid_0,
    input                                      m_axis_tready_0,
    output                                     m_axis_tlast_0,

     // Master Stream Port 1
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata_1,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tstrb_1,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser_1,
    output reg                                 m_axis_tvalid_1,
    input                                      m_axis_tready_1,
    output                                     m_axis_tlast_1,

 
    // Slave Stream Ports (interface to data path upstream)
    input [C_S_AXIS_DATA_WIDTH - 1:0]          s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]  s_axis_tstrb,
    input [C_S_AXIS_TUSER_WIDTH-1:0]           s_axis_tuser,
    input                                      s_axis_tvalid,
    output                                     s_axis_tready,
    input                                      s_axis_tlast,

    // Registers
    input  [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0]  rw_regs,
    output [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0]  rw_defaults,
    input  [NUM_WO_REGS*C_S_AXI_DATA_WIDTH-1:0]  wo_regs,
    output [NUM_WO_REGS*C_S_AXI_DATA_WIDTH-1:0]  wo_defaults,
    input  [NUM_RO_REGS*C_S_AXI_DATA_WIDTH-1:0]  ro_regs
);

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   // ------------- Regs/ wires -----------

   reg [C_M_AXIS_TUSER_WIDTH-1:0]   fifo_1_in_tuser;
   
   wire                             fifo_0_nearly_full;
   wire                             fifo_0_empty;
   reg                              fifo_0_rd_en;
   wire [C_M_AXIS_TUSER_WIDTH-1:0]  fifo_0_out_tuser;
   wire [C_M_AXIS_DATA_WIDTH-1:0]   fifo_0_out_tdata;
   wire [C_M_AXIS_DATA_WIDTH/8-1:0] fifo_0_out_tstrb;
   wire  	                    fifo_0_out_tlast;
   wire                             fifo_0_tvalid;
   wire                             fifo_0_tlast;

   wire                             fifo_1_nearly_full;
   wire                             fifo_1_empty;
   reg                              fifo_1_rd_en;
   reg                              fifo_1_wr_en;			    
   wire [C_M_AXIS_TUSER_WIDTH-1:0]  fifo_1_out_tuser;
   wire [C_M_AXIS_DATA_WIDTH-1:0]   fifo_1_out_tdata;
   wire [C_M_AXIS_DATA_WIDTH/8-1:0] fifo_1_out_tstrb;
   wire  	                    fifo_1_out_tlast;
   wire                             fifo_1_tvalid;
   wire                             fifo_1_tlast;
   
   reg [1:0]                        state;
   reg [1:0]                        state_next;

   wire [7:0] 			    oq_port;
 			    
   // ---------  States ---------------
   localparam S0                    = 0;
   localparam S1                    = 1;
   localparam S2                    = 2;

   // ---------- Interal Parameters -----------------
   localparam BUFFER_SIZE         = 4096; 
   localparam BUFFER_SIZE_WIDTH   = log2(BUFFER_SIZE/(C_M_AXIS_DATA_WIDTH/8));
   localparam MAX_PACKET_SIZE     = 1600;
   localparam BUFFER_THRESHOLD    = (BUFFER_SIZE-MAX_PACKET_SIZE)/(C_M_AXIS_DATA_WIDTH/8);
   
   // ------------ Modules -------------

   fallthrough_small_fifo
   #( .WIDTH(C_M_AXIS_DATA_WIDTH+C_M_AXIS_TUSER_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
      .MAX_DEPTH_BITS(2)
    )
    input_fifo_0
    ( // Outputs
      .dout                         ({fifo_0_out_tlast, fifo_0_out_tuser, 
				      fifo_0_out_tstrb, fifo_0_out_tdata}),
      .full                         (),
      .nearly_full                  (fifo_0_nearly_full),
      .prog_full                    (),
      .empty                        (fifo_0_empty),
      // Inputs
      .din                          ({s_axis_tlast, s_axis_tuser, 
				      s_axis_tstrb, s_axis_tdata}),
      .wr_en                        (s_axis_tvalid & s_axis_tready),
      .rd_en                        (fifo_0_rd_en),
      .reset                        (~axi_aresetn),
      .clk                          (axi_aclk));

    fallthrough_small_fifo
        #( .WIDTH(C_M_AXIS_DATA_WIDTH+C_M_AXIS_TUSER_WIDTH+
		  C_M_AXIS_DATA_WIDTH/8+1),
           .MAX_DEPTH_BITS(BUFFER_SIZE_WIDTH),
           .PROG_FULL_THRESHOLD(BUFFER_THRESHOLD))
      input_fifo_1
        (// Outputs
         .dout                      ({fifo_1_out_tlast, fifo_1_out_tuser,
				      fifo_1_out_tstrb, fifo_1_out_tdata}),
         .full                      (),
         .nearly_full               (),
	 .prog_full                 (fifo_1_nearly_full),
         .empty                     (fifo_1_empty),
         // Inputs
         .din                       ({fifo_0_out_tlast, fifo_1_in_tuser,
				      fifo_0_out_tstrb, fifo_0_out_tdata}),
         .wr_en                     (fifo_1_wr_en),
         .rd_en                     (fifo_1_rd_en),
         .reset                     (~axi_aresetn),
         .clk                       (axi_aclk));
   
   // ------------- Logic ------------

   assign s_axis_tready = !fifo_0_nearly_full;
      // Port 0 wires
   assign m_axis_tuser_0 = fifo_0_out_tuser;
   assign m_axis_tdata_0 = fifo_0_out_tdata;
   assign m_axis_tlast_0 = fifo_0_out_tlast;
   assign m_axis_tstrb_0 = fifo_0_out_tstrb;
      //Port 1 wires
   assign m_axis_tuser_1 = fifo_1_out_tuser;
   assign m_axis_tdata_1 = fifo_1_out_tdata;
   assign m_axis_tlast_1 = fifo_1_out_tlast;
   assign m_axis_tstrb_1 = fifo_1_out_tstrb;
   // output queue port
   assign oq_port        = 8'h80;
   
   always @(*) begin
      fifo_0_rd_en = 0;
      fifo_1_rd_en = 0;
      fifo_1_wr_en = 0;
      m_axis_tvalid_0 = 0;
      m_axis_tvalid_1 = 0;
      state_next = state;
      fifo_1_in_tuser = fifo_0_out_tuser;
			
      case (state)  //Moore machine :-)
	S0: begin
	   m_axis_tvalid_0 = !fifo_0_empty;
	   if (m_axis_tvalid_0 && m_axis_tready_0) begin
	      fifo_0_rd_en = 1;
	      fifo_1_wr_en = 1;
	      fifo_1_in_tuser = {fifo_0_out_tuser[127:32],oq_port,
			       fifo_0_out_tuser[23:0]};
	      state_next = S1;
	   end
        end
        S1: begin
	   m_axis_tvalid_0 = !fifo_0_empty;
	   if (m_axis_tvalid_0 && m_axis_tready_0) begin
	      fifo_0_rd_en = 1;
	      fifo_1_wr_en = 1;
	      if (fifo_0_out_tlast)
		state_next = S2;
	   end
	end
	S2: begin
	   m_axis_tvalid_1 = !fifo_1_empty;
	   if (m_axis_tvalid_1 && m_axis_tready_1) begin
	      fifo_1_rd_en = 1;
	      if (fifo_1_out_tlast)
		state_next = S0;
	   end
	end
      endcase
    end // always @(*)
   
   always @(posedge axi_aclk) begin
      if (~axi_aresetn)
	state <= S0;
      else
	state <= state_next;
   end //always @(posedge axi_aclk)
endmodule
