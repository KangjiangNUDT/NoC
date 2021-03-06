//neuron_cell cintains a router and a neuron
//2017.4.1  fix minor bugs, declare a new wire
//          change localparam to parameter
//2017.4.24 add two parameter SYNTH_PATH and SIM_PATH.

module neuron_cell(clk, rt_clk, rst_n, rt_reset, start,
clk_north, clk_south, clk_east, clk_west,
north_in, south_in, east_in, west_in,
north_neighbor_full, south_neighbor_full, east_neighbor_full, west_neighbor_full,
north_out, south_out, east_out, west_out,
north_full, south_full, east_full, west_full,
write_req_north, write_req_south, write_req_east, write_req_west,
write_en_north, write_en_south, write_en_east, write_en_west);

parameter packet_size = 32;
parameter flit_size = 4;
parameter NUM_NURNS = 2;
parameter NUM_AXONS = 2;
parameter NURN_CNT_BIT_WIDTH = 1;
parameter AXON_CNT_BIT_WIDTH = 1;
parameter X_ID = "1";
parameter Y_ID = "1";
parameter SYNTH_PATH = "D:/code/synth/data";
parameter SIM_PATH =  "D:/code/data";
//parameter MEM_A_MIF_PATH = "D:/code/synth/data1_1/mem_A.mif";
//parameter MEM_B_MIF_PATH = "D:/code/synth/data1_1/mem_B.mif";
//parameter MEM_C_MIF_PATH = "D:/code/synth/data1_1/mem_C.mif";
//parameter BIAS_MIF_PATH = "D:/code/synth/data1_1/Bias.mif";
//parameter MEMBPOT_MIF_PATH = "D:/code/synth/data1_1/MembPot.mif";
//parameter TH_MIF_PATH = "D:/code/synth/data1_1/Th.mif";
//parameter POSTSPIKEHISTORY_MIF_PATH = "D:/code/synth/data1_1/PostSpikeHistory.mif";
//parameter PRESPIKEHISTORY_MIF_PATH = "D:/code/synth/data1_1/PreSpikeHistory.mif";
//parameter WEIGHTS_MIF_PATH = "D:/code/synth/data1_1/Weights.mif";

input clk, rt_clk, clk_north, clk_south, clk_east, clk_west;
input rst_n, rt_reset, start;
input north_neighbor_full, south_neighbor_full, east_neighbor_full, west_neighbor_full;
input write_en_north, write_en_south, write_en_east, write_en_west;
input [flit_size - 1:0] north_in, south_in, east_in, west_in;
output north_full, south_full, east_full, west_full;
output [flit_size - 1:0]  north_out, south_out, east_out, west_out;
output write_req_north, write_req_south, write_req_east, write_req_west;

wire [31:0] SpikePacket;
wire outSpike;
wire [3:0] local_packet_out;
wire local_full, write_req_east, local_neuron_full;
wire [NUM_AXONS - 1:0] spike;
wire write_req_local;

Neuron #(.X_ID(X_ID), .Y_ID(Y_ID), .NUM_NURNS(NUM_NURNS), .NUM_AXONS(NUM_AXONS), .NURN_CNT_BIT_WIDTH(NURN_CNT_BIT_WIDTH), .AXON_CNT_BIT_WIDTH(AXON_CNT_BIT_WIDTH),
        .SYNTH_PATH(SYNTH_PATH),
        .SIM_PATH(SIM_PATH)) 
uut (.clk(clk), .rst_n(rst_n), .SpikePacket(SpikePacket), .outSpike(outSpike),. start(start), .inSpike(spike));

router rt (.clk(rt_clk), .clk_local(clk), .clk_north(clk_north), .clk_south(clk_south), .clk_east(clk_east), .clk_west(clk_west),
.reset(rt_reset), .local_in(SpikePacket), .north_in(north_in), .south_in(south_in), .east_in(east_in), .west_in(west_in),
.local_out(local_packet_out), .north_out(north_out), .south_out(south_out), .east_out(east_out), .west_out(west_out),
.local_full(local_full), .north_full(north_full), .south_full(south_full), .east_full(east_full), .west_full(west_full),
.write_en_local(outSpike), .write_en_north(write_en_north), .write_en_south(write_en_south), .write_en_east(write_en_east), .write_en_west(write_en_west),
.write_req_local(write_req_local), .write_req_north(write_req_north), .write_req_south(write_req_south),
.write_req_east(write_req_east), .write_req_west(write_req_west),
.local_neuron_full(local_neuron_full), .north_neighbor_full(north_neighbor_full), .south_neighbor_full(south_neighbor_full), .east_neighbor_full(east_neighbor_full), .west_neighbor_full(west_neighbor_full));

interface #(.packet_size(packet_size),
            .flit_size(flit_size),
            .x_address_length(8),
            .y_address_length(8),
            .NUM_AXONS(NUM_AXONS),
            .AXON_CNT_BIT_WIDTH(AXON_CNT_BIT_WIDTH)) 
            neu_interface 
            (.router_clk(rt_clk), 
            .neuron_clk(clk), 
            .rst_n(rst_n), 
            .router_reset(rt_reset), 
            .write_en(write_req_local), 
            .start(start), 
            .data_in(local_packet_out), 
            .spike(spike),
            .neuron_full(local_neuron_full));

endmodule