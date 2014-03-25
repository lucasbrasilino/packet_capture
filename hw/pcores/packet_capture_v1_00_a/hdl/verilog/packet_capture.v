/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        packet_capture.v
 *
 *  Library:
 *        hw/contrib/pcores/packet_capture_v1_00_a
 *
 *  Module:
 *        packet_capture
 *
 *  Author:
 *        Lucas Brasilino
 *
 *  Description:
 *        Provides packet capture
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

module packet_capture
#(
    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH=256,
    parameter C_S_AXIS_DATA_WIDTH=256,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXI_DATA_WIDTH=32,
    parameter C_S_AXI_ADDR_WIDTH=32,
    parameter C_USE_WSTRB=0,
    parameter C_DPHASE_TIMEOUT=0,
    parameter C_BASEADDR=32'hFFFFFFFF,
    parameter C_HIGHADDR=32'h00000000,
    parameter C_S_AXI_ACLK_FREQ_HZ=100
)
(
    //Global signals
    input                                      s_axi_aclk,
    input                                      s_axi_aresetn,
    
    // Slave AXI Ports (AXI Lite control/status interface)
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_awaddr,
    input                                     s_axi_awvalid,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_wdata,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   s_axi_wstrb,
    input                                     s_axi_wvalid,
    input                                     s_axi_bready,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     s_axi_araddr,
    input                                     s_axi_arvalid,
    input                                     s_axi_rready,
    output                                    s_axi_arready,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     s_axi_rdata,
    output     [1 : 0]                        s_axi_rresp,
    output                                    s_axi_rvalid,
    output                                    s_axi_wready,
    output     [1 :0]                         s_axi_bresp,
    output                                    s_axi_bvalid,
    output                                    s_axi_awready,
    
    // Master Stream Ports (interface to data path downstream)
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tstrb,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser,
    output                                     m_axis_tvalid,
    input                                      m_axis_tready,
    output                                     m_axis_tlast,

    // Slave Stream Ports (interface to data path upstream)
    input [C_S_AXIS_DATA_WIDTH - 1:0]          s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]  s_axis_tstrb,
    input [C_S_AXIS_TUSER_WIDTH-1:0]           s_axis_tuser,
    input                                      s_axis_tvalid,
    output                                     s_axis_tready,
    input                                      s_axis_tlast
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

   // --------- Internal Parameters ------
   localparam NUM_RW_REGS = 0;
   localparam NUM_WO_REGS = 1;
   localparam NUM_RO_REGS = 1;

   // ------------- Regs/ wires -----------

   //wire [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0] rw_regs;
   //wire [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0] rw_defaults;
   wire [NUM_WO_REGS*C_S_AXI_DATA_WIDTH-1:0] wo_regs;
   //wire [NUM_WO_REGS*C_S_AXI_DATA_WIDTH-1:0] wo_defaults;
   wire [NUM_RO_REGS*C_S_AXI_DATA_WIDTH-1:0] ro_regs;
   
   wire                                            Bus2IP_Clk;
   wire                                            Bus2IP_Resetn;
   wire     [C_S_AXI_ADDR_WIDTH-1 : 0]             Bus2IP_Addr;
   wire                                            Bus2IP_CS;
   wire                                            Bus2IP_RNW;
   wire     [C_S_AXI_DATA_WIDTH-1 : 0]             Bus2IP_Data;
   wire     [C_S_AXI_DATA_WIDTH/8-1 : 0]           Bus2IP_BE;
   wire     [C_S_AXI_DATA_WIDTH-1 : 0]             IP2Bus_Data;
   wire                                            IP2Bus_RdAck;
   wire                                            IP2Bus_WrAck;
   wire                                            IP2Bus_Error;

   wire [C_M_AXIS_DATA_WIDTH - 1:0] 	     m_axis_tdata_0;
   wire [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0]  m_axis_tstrb_0;
   wire [C_M_AXIS_TUSER_WIDTH-1:0] 	         m_axis_tuser_0;
   wire                                      m_axis_tvalid_0;
   wire                                      m_axis_tready_0;
   wire                                      m_axis_tlast_0;

   wire [C_M_AXIS_DATA_WIDTH - 1:0] 	     m_axis_tdata_1;
   wire [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0]  m_axis_tstrb_1;
   wire [C_M_AXIS_TUSER_WIDTH-1:0] 	         m_axis_tuser_1;
   wire                                      m_axis_tvalid_1;
   wire                                      m_axis_tready_1;
   wire                                      m_axis_tlast_1;

   // ------------ Modules -------------

 // -- AXILITE IPIF
  axi_lite_ipif_1bar #
  (
   .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
   .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
    .C_USE_WSTRB        (C_USE_WSTRB),
    .C_DPHASE_TIMEOUT   (C_DPHASE_TIMEOUT),
   .C_BAR0_BASEADDR    (C_BASEADDR),
   .C_BAR0_HIGHADDR    (C_HIGHADDR)
  ) axi_lite_ipif_inst
  (
    .S_AXI_ACLK          ( s_axi_aclk     ),
    .S_AXI_ARESETN       ( s_axi_aresetn  ),
    .S_AXI_AWADDR        ( s_axi_awaddr   ),
    .S_AXI_AWVALID       ( s_axi_awvalid  ),
    .S_AXI_WDATA         ( s_axi_wdata    ),
    .S_AXI_WSTRB         ( s_axi_wstrb    ),
    .S_AXI_WVALID        ( s_axi_wvalid   ),
    .S_AXI_BREADY        ( s_axi_bready   ),
    .S_AXI_ARADDR        ( s_axi_araddr   ),
    .S_AXI_ARVALID       ( s_axi_arvalid  ),
    .S_AXI_RREADY        ( s_axi_rready   ),
    .S_AXI_ARREADY       ( s_axi_arready  ),
    .S_AXI_RDATA         ( s_axi_rdata    ),
    .S_AXI_RRESP         ( s_axi_rresp    ),
    .S_AXI_RVALID        ( s_axi_rvalid   ),
    .S_AXI_WREADY        ( s_axi_wready   ),
    .S_AXI_BRESP         ( s_axi_bresp    ),
    .S_AXI_BVALID        ( s_axi_bvalid   ),
    .S_AXI_AWREADY       ( s_axi_awready  ),
    
    // Controls to the IP/IPIF modules
    .Bus2IP_Clk          ( Bus2IP_Clk     ),
    .Bus2IP_Resetn       ( Bus2IP_Resetn  ),
    .Bus2IP_Addr         ( Bus2IP_Addr    ),
    .Bus2IP_RNW          ( Bus2IP_RNW     ),
    .Bus2IP_BE           ( Bus2IP_BE      ),
    .Bus2IP_CS           ( Bus2IP_CS      ),
    .Bus2IP_Data         ( Bus2IP_Data    ),
    .IP2Bus_Data         ( IP2Bus_Data    ),
    .IP2Bus_WrAck        ( IP2Bus_WrAck   ),
    .IP2Bus_RdAck        ( IP2Bus_RdAck   ),
    .IP2Bus_Error        ( IP2Bus_Error   )
  );
  
  // -- IPIF REGS
  ipif_regs #
  (
    .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),          
    .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
    .NUM_WO_REGS        (NUM_WO_REGS),
    .NUM_RO_REGS        (NUM_RO_REGS)
  ) ipif_regs_inst
  (   
    .Bus2IP_Clk     ( Bus2IP_Clk     ),
    .Bus2IP_Resetn  ( Bus2IP_Resetn  ), 
    .Bus2IP_Addr    ( Bus2IP_Addr    ),
    .Bus2IP_CS      ( Bus2IP_CS      ),
    .Bus2IP_RNW     ( Bus2IP_RNW     ),
    .Bus2IP_Data    ( Bus2IP_Data    ),
    .Bus2IP_BE      ( Bus2IP_BE      ),
    .IP2Bus_Data    ( IP2Bus_Data    ),
    .IP2Bus_RdAck   ( IP2Bus_RdAck   ),
    .IP2Bus_WrAck   ( IP2Bus_WrAck   ),
    .IP2Bus_Error   ( IP2Bus_Error   ),
    
    .wo_regs        ( wo_regs ),
    .ro_regs        ( ro_regs )
  );

   packet_duplic #
   (
     .C_M_AXIS_DATA_WIDTH  (C_M_AXIS_DATA_WIDTH),
     .C_S_AXIS_DATA_WIDTH  (C_S_AXIS_DATA_WIDTH),
     .C_M_AXIS_TUSER_WIDTH (C_M_AXIS_TUSER_WIDTH),
     .C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),

     .NUM_RW_REGS          (NUM_RW_REGS),
     .NUM_WO_REGS          (NUM_WO_REGS),
     .NUM_RO_REGS          (NUM_RO_REGS)
   )
     packet_duplic
       (
         // Global Ports
         .axi_aclk      (s_axi_aclk),
         .axi_aresetn   (s_axi_aresetn),

         // Master Stream Port 0
         .m_axis_tdata_0  (m_axis_tdata_0),
         .m_axis_tstrb_0  (m_axis_tstrb_0),
         .m_axis_tuser_0  (m_axis_tuser_0),
         .m_axis_tvalid_0 (m_axis_tvalid_0),
         .m_axis_tready_0 (m_axis_tready_0),
         .m_axis_tlast_0  (m_axis_tlast_0),

	      // Master Stream Port 1
         .m_axis_tdata_1  (m_axis_tdata_1),
         .m_axis_tstrb_1  (m_axis_tstrb_1),
         .m_axis_tuser_1  (m_axis_tuser_1),
         .m_axis_tvalid_1 (m_axis_tvalid_1),
         .m_axis_tready_1 (m_axis_tready_1),
         .m_axis_tlast_1  (m_axis_tlast_1),


         // Slave Stream Ports (interface to RX queues)
         .s_axis_tdata  (s_axis_tdata),
         .s_axis_tstrb  (s_axis_tstrb),
         .s_axis_tuser  (s_axis_tuser),
         .s_axis_tvalid (s_axis_tvalid),
         .s_axis_tready (s_axis_tready),
         .s_axis_tlast  (s_axis_tlast),

         // Registers
         /*
         .rw_regs       (rw_regs),
         .rw_defaults   (rw_defaults),
         .wo_regs       (wo_regs),
         .wo_defaults   (wo_defaults),
         */
         .wo_regs       (wo_regs),
         .ro_regs       (ro_regs)
       );

   /* Unfortunatelly, input_arbiter doesn't deal very well with
      queues number other than the default*/
   input_arbiter
     input_arbiter
   (
    // Clock and Reset - Global signals
    .axi_aclk      (s_axi_aclk),
    .axi_aresetn   (s_axi_aresetn),

    .m_axis_tdata (m_axis_tdata),
    .m_axis_tstrb (m_axis_tstrb),
    .m_axis_tuser (m_axis_tuser),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tlast (m_axis_tlast),
    
    .s_axis_tdata_0 (m_axis_tdata_0),
    .s_axis_tstrb_0 (m_axis_tstrb_0),
    .s_axis_tuser_0 (m_axis_tuser_0),
    .s_axis_tvalid_0 (m_axis_tvalid_0),
    .s_axis_tready_0 (m_axis_tready_0),
    .s_axis_tlast_0 (m_axis_tlast_0),

    .s_axis_tdata_1 (m_axis_tdata_1),
    .s_axis_tstrb_1 (m_axis_tstrb_1),
    .s_axis_tuser_1 (m_axis_tuser_1),
    .s_axis_tvalid_1 (m_axis_tvalid_1),
    .s_axis_tready_1 (m_axis_tready_1),
    .s_axis_tlast_1 (m_axis_tlast_1)
/*
    .s_axis_tdata_2 ({C_S_AXIS_DATA_WIDTH{1'b0}}),
    .s_axis_tstrb_2 ({(C_S_AXIS_DATA_WIDTH/8){1'b0}}),
    .s_axis_tuser_2 ({C_S_AXIS_TUSER_WIDTH{1'b0}}),
    .s_axis_tvalid_2 (1'b0),
    .s_axis_tready_2 (),
    .s_axis_tlast_2 (1'b0),

    .s_axis_tdata_3 ({C_S_AXIS_DATA_WIDTH{1'b0}}),
    .s_axis_tstrb_3 ({(C_S_AXIS_DATA_WIDTH/8){1'b0}}),
    .s_axis_tuser_3 ({C_S_AXIS_TUSER_WIDTH{1'b0}}),
    .s_axis_tvalid_3 (1'b0),
    .s_axis_tready_3 (),
    .s_axis_tlast_3 (1'b0),

    .s_axis_tdata_4 ({C_S_AXIS_DATA_WIDTH{1'b0}}),
    .s_axis_tstrb_4 ({(C_S_AXIS_DATA_WIDTH/8){1'b0}}),
    .s_axis_tuser_4 ({C_S_AXIS_TUSER_WIDTH{1'b0}}),
    .s_axis_tvalid_4 (1'b0),
    .s_axis_tready_4 (),
    .s_axis_tlast_4 (1'b0)
 */
    );
   
endmodule
