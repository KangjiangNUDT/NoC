//------------------------------------------------------------------------
// Title       : data path
// Version     : 0.1
// Author      : Khadeer Ahmed
// Date created: 12/13/2016
// -----------------------------------------------------------------------
// Discription : data path for the neuron
// NurnTyp_i: 0: I&F
//			  1: ReLU
// NOTE:
// 		the priority quantization is not parameterized. if integer/fraction
// 		data  width is greater than 32 bits then additional entries in the 
// 		quantization LUT must be added
// -----------------------------------------------------------------------
// Maintainance History
// -ver x.x : date : auth
//		details
//------------------------------------------------------------------------

//2017.4.29 PreSpikeHist_Ppln[3] has multiple drive. Fixed it.		
//2017.5.10 add new signal: update_weight_enable in learn pipeline. if enLTD/enLTP is enabled, update_weight_enable is high
//			It is used to control weight memory write enable signal generated by controller. These two signal are sent into
//			a AND gate. if update_weight_enable is 0, weight won't be updated.
//			Issue: timing of update_weight_enable is not correct, it's not aligned weight memory write enable signal.
//			it's earlier than weight memory write enable signal. need to fix it by adding a new pipeline. 
//2017.8.30 post spike history updating logic is different from spnsim. Spnsim compares post spike history and determin if it's valid first,
//			and then increases post history. In datapath, post spike history increases first and then datapath check if it's valid.
//			This difference doesn't matter, increase ltd window by 1, behavior will be same as spnsim.
//2017.8.31 Add input:shift_writeback_en_buffer_i. 3 registers: shift_writeback_en_buffer_i_dealy1 and hift_writeback_en_buffer_i_dealy2,
//			weight_writeback_enable_buffer. weight write back signal is 4 clocks laters than update_weight_enable. So weight_writeback_enable_buffer
//			is a 4 bit width shift register to make sure update_weight_enable signal and weight write back signal arrive at same time. weight_writeback_enable_buffer is
//			controlled by signal generated by controller.
//			Accoring to simulation with 4 neuron and 4 axon, waveform looks correct.
//2017.9.6  Wrong condition for LTD and LTP.
//201709.7  Big changes to fix post history problem.
//				1, add temp_LTD_win to store LTD window. 
//				2, expired_post_history is LTD window + 1. When need to expire post history, this value is written to status memory.
//				3, post_history_mux, a mux to select actual post history or expired post history. select signal is expired_post_history_write_back_i,
//				   when 1, select expired post history. when 0 select actual post history.
//				4, sel_wrBackStat_B_mux, mux to select sel_wrBackStat_B_i or 2b'11. It is determined by expired_post_history_write_back_i.
//                 sel_wrBackStat_B_mux determines what will be sent to data_StatWr_B_o. 
//				   Problem: sel_wrBackStat_B_mux might be a critical path.
//				5, expPostHist, a flag to indicate whether to expire post history.
//				6, en_expired_post_history_write_back determines whether to write back expired post history.
//			Accoring to timing diagram, looks right, need testbench to verify.
//2017.9.16  Remove sel_wrBackStat_B_mux, controller can generate right select signal.
//2017.9.16  Add a register to delay lrnoutspike(the spike generaetd at current tick) 2 clocks for LTP/LTD condition.
//			 change condition of determining LTP/LTP
//2017.9.21  Add a register, add_sub_flag and a mux. When ltp, wi = wi + delta_w, when ltd wi = wi - delta_w.
//			quant_Dlta_Wt_Bias_reg holds delta_w, but it's always a positive value. This mux is controlled by
//			add_sub_flag, so that positive or negative can be stored in quant_Dlta_Wt_Bias_reg.
//2017.9.25  Fixed pre history updating logic. Pre history updating condition was not exactly the same as spnsim. Fixed it.
//			 Fixed a problem with PreSpikeHist_Ppln. Previously PreSpikeHist_Ppln[4] can't pass to PreSpikeHist_Ppln[3] when expPreHist == 1'b1;
//			 It was incorrect. 
//			 Fixed weight write back bug, remove shift_writeback_en_buffer_i_dealy1 and shift_writeback_en_buffer_i_dealy2. 
//			 weight_writeback_enable_buffer doesn't have to be controlled. Just let it shift every clock.
//2017.9.27  remove shift_writeback_en_buffer_i port, it's not needed
//2017.9.28  Add bufBias_delay. bias computation pipeline get wrong bias. bufBias is updated too early. When recall FSM at acc membpot state,
//			 buffBias_o is 1, and net clock bufBias is updated. However, at this time bias learning pipeline has not started yet.
//			 When start to learn neuron 0 bias, neuron 1's bias is already sent into pipeline. 
//			 bufBias_delay is used to delay bias for 2 clocks. so pipeline get correct bias from bufBias_delay.
//			 checked whole pipeline, flag and control signal are correct. But the condition which determins LTP/LTD for bias is wrong.
//2017.9.29  Condition which determines LTD/LTP for bias learning was wrong. Changed condition. addition suctraction flag for bias pipeline is added.
//			 Otherwise, pipeline cannot perform subtraction.
//2017.9.30  add expired_post_history_write_back_delay. it's used to reset expPostHist. Add method to reset expPostHist.
//			 change en_expired_post_history_write_back_o. Tested with bias learning mode and weight learning at same time.
//			 works correctly for fist 15 steps. Comparator cannot compare negative value correctly.
//2017.10.8  Add signd_comparator to compare threshold. change the condition of releasing spike.
//2017.10.17 Find a bug, expPostHist sometimes is high incorrectly because the LTP/LTP condition pipeline always works even if learning is
//			 not started. There is no mechanism to set expPostHist to 0 when learning is working. 
//			 Add a new signal from controller, which is high when learning weight. So expPostHist is always 0 when not lerning weight.
//2017.11.13 fix random threshold mode. ramdom threshold is the sum of a fixed threshold and a random number.random threshold is computed by DELTA_WT_BIAS_ADDER.
//			 previously, this adder add bufTh and random numebr generated by lfsr. use fixedTh to replace bufTh.
//			 (rdLFSR_dly[0] & outSpike_o) is used to shift lfsr to get new value. This signal and write_enable_threshold are 1 at same time
//			 the old value of lfsr is added with threshold. new value is obtained 1 clk later ans will be used for next neuron
//Todo:
//2017.9.7  enLTD and enLTP conditions need to be checked, may need change.
//			Verify post spike history.

`include "neuron_define.v"
// `timescale 1ns/100ps
// `define RECORD_SPIKE

module dataPath
#(
	parameter X_ID = "1",
	parameter Y_ID = "1",
	parameter DIR_ID = {X_ID, "_", Y_ID},
	parameter SIM_PATH = "D:/code/data",
	parameter STOP_STEP = 5,

	parameter NUM_NURNS    = 256  ,
	parameter NUM_AXONS    = 256  ,

	parameter DATA_BIT_WIDTH_INT    = 8 ,
	parameter DATA_BIT_WIDTH_FRAC   = 8 ,

	parameter NURN_CNT_BIT_WIDTH   = 8 ,
	parameter AXON_CNT_BIT_WIDTH   = 8 ,

	parameter STDP_WIN_BIT_WIDTH = 8 ,
	
	parameter AER_BIT_WIDTH = 32 ,

	parameter PRIORITY_ENC_OUT_BIT_WIDTH = 3,

	parameter DSIZE = DATA_BIT_WIDTH_INT + DATA_BIT_WIDTH_FRAC,

	parameter SEED = 0
)
(
	input 													clk_i			,
	input 													rst_n_i			,

	//config memory
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	RstPot_i		,
	input 													NurnType_i 		,
	input 													RandTh_i 		,
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	Th_Mask_i		,
	input  [STDP_WIN_BIT_WIDTH-1:0] 						LTP_Win_i		,
	input  [STDP_WIN_BIT_WIDTH-1:0] 						LTD_Win_i		,
	input  													axonLrnMode_i 	,
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	LTP_LrnRt_i		,
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	LTD_LrnRt_i		,
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0]		FixedThreshold_i,

	//status memory
	//input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	data_StatRd_A_i	,
	input  [STDP_WIN_BIT_WIDTH-1:0] 						data_StatRd_C_i	,
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	data_StatRd_E_i	,
	input  [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	data_StatRd_F_i	,

	//output reg [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] data_StatWr_B_o	,
	output [STDP_WIN_BIT_WIDTH-1:0] 						data_StatWr_D_o	,
	output [DATA_BIT_WIDTH_INT+DATA_BIT_WIDTH_FRAC-1:0] 	data_StatWr_G_o	,

	input [DSIZE-1:0]										data_rd_bias_i,
	input [DSIZE-1:0]										data_rd_potential_i,
	input [DSIZE-1:0]										data_rd_threshold_i,
	input [STDP_WIN_BIT_WIDTH-1:0]							data_rd_posthistory_i,

	output reg [DSIZE-1:0]									data_wr_bias_o,
	output reg [DSIZE-1:0]									data_wr_potential_o,
	output reg [DSIZE-1:0]									data_wr_threshold_o,
	output reg [STDP_WIN_BIT_WIDTH-1:0]						data_wr_posthistory_o,

	//in spike buffer
	input 													rcl_inSpike_i	,
	input 													lrn_inSpike_i	,

	//Router
	output 													outSpike_o 		,

	//controller
	input 													rstAcc_i 		,
	input 													accEn_i 		,
	input 													cmp_th_i 		,
	input  [1:0]											sel_rclAdd_B_i 	,
	input  [1:0]											sel_wrBackStat_B_i,
	input 													buffMembPot_i 	,
	input 													updtPostSpkHist_i,
	input 													addLrnRt_i 		,
	input 													enQuant_i 		,
	input 													buffBias_i 		,
	input 													lrnUseBias_i 	,
	input 													cmpSTDP_i 		,
	//input													shift_writeback_en_buffer_i,
	input													expired_post_history_write_back_i,
	input													enLrnWtPipln_i,

	`ifdef DUMP_OUTPUT_SPIKE
	input													start_i,
	`endif

	`ifdef AER_MULTICAST
	output													th_compare_o,
	`endif
	
	output													update_weight_enable_o,
	output													en_expired_post_history_write_back_o

);
	

	//SELECT LINE ENCODING
	//--------------------------------------------------//
	//recall adder select lines
	parameter [1:0] RCL_ADD_B_WT       = 2'b00;
	parameter [1:0] RCL_ADD_B_BIAS     = 2'b01;
	parameter [1:0] RCL_ADD_B_MEMB_POT = 2'b10;
	parameter [1:0] RCL_ADD_B_NEG_TH   = 2'b11;

	//status port B writeback select lines
	parameter [1:0] WR_BACK_STAT_B_BIAS      = 2'b00;
	parameter [1:0] WR_BACK_STAT_B_MEMB_POT  = 2'b01;
	parameter [1:0] WR_BACK_STAT_B_TH        = 2'b10;
	parameter [1:0] WR_BACK_STAT_B_POST_HIST = 2'b11;

	//REGISTER DECLARATION
	//--------------------------------------------------//
	reg [DSIZE-1:0]	AccReg, rclAdd_A, rclAdd_B;
	reg [DSIZE-1:0]	bufMembPot, bufBias, bufTh;
	reg comp_out, lrnOutSpikeReg, enLTP, enLTD, expPreHist/* synthesis preserve */;
	reg [1:0] rclOutSpikeReg_dly, rdLFSR_dly/* synthesis noprune */;
	reg [STDP_WIN_BIT_WIDTH-1:0] PostSpkHist;
	reg [STDP_WIN_BIT_WIDTH-1:0] PreSpikeHist_Ppln[0:4] /* synthesis noprune */;
	reg [DSIZE-1:0] WeightBias_Ppln[0:2];
	reg [DSIZE-1:0] updtReg_WeightBias, delta_WtBias;
	reg [4:0] enLrn_Ppln;
	reg [DSIZE-1:0] eta_prime, sign_WtBias, quant_Dlta_Wt_Bias_reg/* synthesis noprune */;
	reg [DATA_BIT_WIDTH_INT-2:0] pEnc_in;
	reg shiftRight, shiftRight_dly, deltaAdder_signed;
	reg [PRIORITY_ENC_OUT_BIT_WIDTH-1:0] quantVal/* synthesis preserve */;
	reg [DSIZE-1:0] deltaAdder_inA, deltaAdder_inB;
	reg [STDP_WIN_BIT_WIDTH-1:0] preSpikeHist;
	reg valid_PreHist, lrnUseBias_dly;
	reg update_weight_enable;

	reg [3:0] weight_writeback_enable_buffer;
	//reg shift_writeback_en_buffer_i_dealy1;
	//reg shift_writeback_en_buffer_i_dealy2;
	reg expPostHist;

	reg [STDP_WIN_BIT_WIDTH-1:0] temp_LTD_win;
	reg [STDP_WIN_BIT_WIDTH-1:0] expired_post_history;
	reg [STDP_WIN_BIT_WIDTH-1:0] post_history_mux;
	reg en_expired_post_history_write_back;
	reg [1:0] lrnOutSpikeReg_delay;
	reg [2:0] add_sub_flag;

	reg [DSIZE-1:0] bufBias_delay[1:0];
	reg expired_post_history_write_back_delay;


	//WIRE DECLARATION
	//--------------------------------------------------//
	wire [DSIZE-1:0] lfsr_data, delta_WtBias_Th, quant_Dlta_Wt_Bias;
	wire [DSIZE:0] negTh, negWtBias, negDelta_WtBias;
	wire valid_PostHist, CorSpike;
	wire [DATA_BIT_WIDTH_INT-1:0] shifter_in_int;
	wire [DATA_BIT_WIDTH_FRAC-1:0] shifter_in_frac;
	wire [PRIORITY_ENC_OUT_BIT_WIDTH-1:0] pEnc_out;
	wire [DSIZE-1:0] updt_WeightBias, WtBias_in, accIn;
	wire [DSIZE-STDP_WIN_BIT_WIDTH-1:0] postSpike_pad;
	wire threshold_equal, threshold_greater;

	integer i;

	//LOGIC
	//--------------------------------------------------//

	//registers
	always @(posedge clk_i or negedge rst_n_i) begin
		if (rst_n_i == 1'b0) begin
			AccReg <= 0;
			bufMembPot <= 0;
			bufBias <= 0;
			rclOutSpikeReg_dly <= 2'b0;
			bufTh <= 0;
			lrnOutSpikeReg <= 0;
			rdLFSR_dly <= 2'b0;
			PostSpkHist <= 0;
			temp_LTD_win <= 1'b0;
			expired_post_history_write_back_delay <= 1'b0;
		end else begin
			expired_post_history_write_back_delay <= expired_post_history_write_back_i;
			if (rstAcc_i == 1'b1) begin
				AccReg <= 0;
			end else if (accEn_i) begin
				AccReg <= accIn;
			end

			if (buffMembPot_i == 1'b1) begin
				bufMembPot <= AccReg;
			end

			if (buffBias_i == 1'b1) begin
				// bufBias <= data_StatRd_A_i;
				bufBias <= data_rd_bias_i;
			end

			if (cmp_th_i == 1'b1) begin
				// bufTh <= data_StatRd_A_i;
				bufTh <= data_rd_threshold_i;
				rclOutSpikeReg_dly <= {comp_out,comp_out};
				lrnOutSpikeReg <= comp_out;
			end else begin
				rclOutSpikeReg_dly <= {1'b0,rclOutSpikeReg_dly[1]};
			end
			rdLFSR_dly <= {cmp_th_i,rdLFSR_dly[1]};

			//post spike history
			if (updtPostSpkHist_i == 1'b1) begin
				if (lrnOutSpikeReg == 1'b1) begin
					PostSpkHist <= 0;
				end else if (comp_out == 1'b1) begin
					// PostSpkHist <= data_StatRd_A_i[STDP_WIN_BIT_WIDTH-1:0] + 1;
					PostSpkHist <= data_rd_posthistory_i + 1;
				end else begin
					// PostSpkHist <= data_StatRd_A_i[STDP_WIN_BIT_WIDTH-1:0];
					PostSpkHist <= data_rd_posthistory_i;
				end
				temp_LTD_win <= LTD_Win_i;
			end
		end
	end
	assign outSpike_o = rclOutSpikeReg_dly[0] & (~rclOutSpikeReg_dly[1]);//generates a pulse

`ifdef AER_MULTICAST
	//assign th_compare_o = rclOutSpikeReg_dly[1];
	assign th_compare_o = comp_out;
`endif

	//expired post synaptic history
	always @(*)
		begin
			expired_post_history = temp_LTD_win + 1;
		end

	//mux to select post synaptic history or expired post synaptic history
	always @(*)
		begin
			if (expired_post_history_write_back_i == 1'b0)
				post_history_mux = PostSpkHist;
			else
				post_history_mux = expired_post_history;
		end
	
	//recall adder inputs
	//assign negTh = (~data_StatRd_A_i) + 1;
	assign negTh = (~data_rd_threshold_i) + 1;
	always @(*)	begin
		//port A
		rclAdd_A = AccReg;

		//Port B
		case (sel_rclAdd_B_i)
			RCL_ADD_B_WT      : rclAdd_B = (rcl_inSpike_i == 1'b1) ? data_StatRd_E_i : 0;
			// RCL_ADD_B_BIAS    : rclAdd_B = data_StatRd_A_i;
			// RCL_ADD_B_MEMB_POT: rclAdd_B = data_StatRd_A_i;
			RCL_ADD_B_BIAS    : rclAdd_B = data_rd_bias_i;
			RCL_ADD_B_MEMB_POT: rclAdd_B = data_rd_potential_i;
			default           : rclAdd_B = negTh[DSIZE-1:0];//RCL_ADD_B_NEG_TH
		endcase

	end

	// Comparator:
	// 1) Recall  : Compare Threshold & Accumulated MembPot
	// 2) Learning: Compare Post Synaptic Tracker and Pre Synaptic Tracker history
	//              to select LTP or LTD Learning Rate
	//              Based on LTP or LTD, Weight's 2's compliments will be used in learning Adder1  
	always@(*) begin
		comp_out  =  1'b0 ;
		if(cmp_th_i == 1'b1) begin
			//if(AccReg >= data_StatRd_A_i) begin
			if( (threshold_equal || threshold_greater ) == 1'b1) begin//change to 2's complement comparator
				comp_out  =  1'b1 ;
			end
		end

		if (updtPostSpkHist_i == 1'b1) begin
			//if (data_StatRd_A_i[STDP_WIN_BIT_WIDTH-1:0] <= LTD_Win_i) begin
			if (data_rd_posthistory_i <= LTD_Win_i) begin
				comp_out  =  1'b1 ;
			end
		end
	end


	//writeback
	// assign postSpike_pad = 0;
	// always@(*) begin
	// 	case(sel_wrBackStat_B_i)
	// 		WR_BACK_STAT_B_BIAS: begin 
	// 		 	data_StatWr_B_o = updtReg_WeightBias; 
	// 		end
	// 		WR_BACK_STAT_B_MEMB_POT: begin
	// 			if (rclOutSpikeReg_dly[0] == 1'b1) begin
	// 				if (NurnType_i == 1'b1) begin
	// 					data_StatWr_B_o = AccReg;
	// 				end else begin
	// 					data_StatWr_B_o = RstPot_i;	
	// 				end
	// 			end else begin
	// 				data_StatWr_B_o = bufMembPot;
	// 			end
	// 		end 
	// 		WR_BACK_STAT_B_TH: begin
	// 			data_StatWr_B_o = bufTh;
	// 			if (rclOutSpikeReg_dly[0] == 1'b1) begin
	// 				if (RandTh_i == 1'b1) begin
	// 					data_StatWr_B_o = delta_WtBias_Th;	
	// 				end
	// 			end
	// 		end
	// 		default: begin //WR_BACK_STAT_B_POST_HIST
	// 			//data_StatWr_B_o = {postSpike_pad,PostSpkHist}; 
	// 			data_StatWr_B_o = {postSpike_pad,post_history_mux}; 
	// 		end 
	// 	endcase
	// end

	always @(*)
		begin
			data_wr_bias_o = updtReg_WeightBias; 

			if (rclOutSpikeReg_dly[0] == 1'b1) 
				begin
					if (NurnType_i == 1'b1)
						data_wr_potential_o = AccReg;
					else
						data_wr_potential_o = RstPot_i;	
				end 
			else
				data_wr_potential_o = bufMembPot;

			if (rclOutSpikeReg_dly[0] == 1'b1) 
				begin
					if (RandTh_i == 1'b1)
						data_wr_threshold_o = delta_WtBias_Th;
					else
						data_wr_threshold_o = bufTh;
				end
			else
				data_wr_threshold_o = bufTh;

			data_wr_posthistory_o = post_history_mux;
		end

	assign data_StatWr_D_o = PreSpikeHist_Ppln[0];
	assign data_StatWr_G_o = updtReg_WeightBias;

	//DELTA_WT_BIAS_ADDER input mux
	always @ (*) begin
		case(sel_wrBackStat_B_i)
			WR_BACK_STAT_B_TH: begin
				deltaAdder_inA = (lfsr_data & Th_Mask_i);
				//deltaAdder_inB = bufTh;
				//use FixedThreshold_i to replace bufTh. Musr guarantee the value in initial threshold memory are the same as FixedThreshold memory
				deltaAdder_inB = FixedThreshold_i;
				deltaAdder_signed = 1'b0;
			end
			default: begin
				deltaAdder_inA = eta_prime;
				deltaAdder_inB = sign_WtBias;
				deltaAdder_signed = 1'b1;
			end
		endcase
	end

	//STDP tracking
	assign valid_PostHist = (PostSpkHist <= LTD_Win_i) ? 1'b1 : 1'b0;
	assign CorSpike = (preSpikeHist >= PostSpkHist) ? 1'b1 : 1'b0;//corelated spike

	//mismatch
	//in spnsim pre history updated first, and the new pre history compare with window
	//When pre_history = window, in spnsim, new history is window + 1 and valid_pre is false
	//Here when pre_history = window, valid_pre is true, expired history written into memory
	always @ (*) begin
		
		if (lrn_inSpike_i == 1'b1) begin
			preSpikeHist = 0;
			valid_PreHist = 1'b1;
		end else begin
		// mismatch with SpnSim
			if (data_StatRd_C_i > LTP_Win_i) begin
				preSpikeHist = data_StatRd_C_i;
				valid_PreHist = 1'b0;
			end else begin //if (data_StatRd_C_i <= LTP_Win_i)
				if (data_StatRd_C_i == LTP_Win_i)
					begin
						preSpikeHist = data_StatRd_C_i + 1;
						valid_PreHist = 1'b0;
					end
				else
					begin
						preSpikeHist = data_StatRd_C_i + 1;
						valid_PreHist = 1'b1;
					end
			end
		end
	end

	//eta_prime +/- weight data mux and priority encoder input
	assign WtBias_in = (lrnUseBias_dly == 1'b0) ? data_StatRd_F_i : bufBias_delay[0];
	assign negWtBias = (~WtBias_in) + 1;
	assign negDelta_WtBias = (~delta_WtBias) + 1;
	always @ (*) begin
		if (enLTP == 1'b1) begin
			eta_prime = LTP_LrnRt_i;
			sign_WtBias =  negWtBias[DSIZE-1:0];
			end 
		//end else begin //if (enLTD == 1'b1)   bug: enLTD is not used
		else if (enLTD == 1'b1) 
			begin
			eta_prime = LTD_LrnRt_i;
			sign_WtBias =  WtBias_in;
			end
		else	//prevent latch
			begin
			eta_prime = 0;
			sign_WtBias =  0;
			end

		if (delta_WtBias[DSIZE-1] == 1'b1) begin
			shiftRight = 1'b1;
			pEnc_in = negDelta_WtBias[DSIZE-2:DATA_BIT_WIDTH_FRAC];
		end else begin
			shiftRight = 1'b0;
			pEnc_in = delta_WtBias[DSIZE-2:DATA_BIT_WIDTH_FRAC];
		end
	end
	assign shifter_in_int = 1;
	assign shifter_in_frac = 0;

	//quantization look up
	always @ (posedge clk_i or negedge rst_n_i) begin
		if (rst_n_i == 1'b0) begin
			quantVal <= 0;
		end else begin
			case (pEnc_out)
				1: quantVal <= 2;
				2: quantVal <= 4;
				3: quantVal <= 8;
				4: quantVal <= 16;
				5: quantVal <= 32;
				default: quantVal <= 0;
			endcase
		end
	end

	//learn pipeline reg
	always @(posedge clk_i or negedge rst_n_i) begin
		if (rst_n_i == 1'b0) begin
			enLTP <= 1'b0;
			enLTD <= 1'b0;
			expPreHist <= 1'b0;

			delta_WtBias <= 0;
			quant_Dlta_Wt_Bias_reg <= 0;

			weight_writeback_enable_buffer <= 0;
			//shift_writeback_en_buffer_i_dealy1 <= 1'b0;
			//shift_writeback_en_buffer_i_dealy2 <= 1'b0;
			update_weight_enable <= 1'b0;

			for(i = 0; i <= 4; i = i + 1)
				PreSpikeHist_Ppln[i] <= 0;
			enLrn_Ppln <= 5'b0;
			shiftRight_dly <= 1'b0;
			lrnUseBias_dly <= 1'b0;
			for(i = 0; i <= 2; i = i + 1)
				WeightBias_Ppln[i] <= 0;
			updtReg_WeightBias <= 0;

			expPostHist <= 1'b0;
			en_expired_post_history_write_back <= 1'b0;
			lrnOutSpikeReg_delay <= 2'b0;
			add_sub_flag <= 3'b0;

			bufBias_delay[0] <= 0;
			bufBias_delay[1] <= 0;
		
		end else begin

			enLTP <= 1'b0;
			enLTD <= 1'b0;
			expPreHist <= 1'b0;
			update_weight_enable <= 1'b0;
			//expPostHist <= 1'b0;
			//bug: if condition mismatch with SpnSim
			if ((axonLrnMode_i == 1'b1) && (lrnUseBias_i == 1'b0)) begin
				//SpnSim: if ((pending_out_spikes[i] == 1) && (valid_PreHist == true))
				//two options: 1, PostSpkHist is 1 when a spike is generated. 2, add a new pipeline to store post spikes.
				if ((lrnOutSpikeReg_delay[0] == 1'b1) && (valid_PreHist == 1'b1) ) begin
					enLTP <= 1'b1;
					expPreHist <= 1'b1;
					update_weight_enable <= 1'b1;
					add_sub_flag[2] <= 1'b0;
				//SpnSim: else if ((pending_out_spikes[i] == 1) && (valid_PreHist == false))
				end else if ((lrnOutSpikeReg_delay[0] == 1'b1) && (valid_PreHist == 1'b0)) begin
					enLTD <= 1'b1;
					update_weight_enable <= 1'b1;
					add_sub_flag[2] <= 1'b1;
				//SpnSim: else if ((valid_PostHist == true) && (*in_spikes[i][j] == 1))
				end else if ((valid_PostHist == 1'b1) && (lrn_inSpike_i == 1'b1) ) begin
					enLTD <= 1'b1;
					//expPreHist <= 1'b1;
					update_weight_enable <= 1'b1;
					expPostHist <= 1'b1 & enLrnWtPipln_i;
					add_sub_flag[2] <= 1'b1;
				end
			end else if (lrnUseBias_i == 1'b1) begin
				if (lrnOutSpikeReg_delay[0] == 1'b1) begin
					enLTP <= 1'b1;
					add_sub_flag[2] <= 1'b0;
				end else begin
					enLTD <= 1'b1;
					add_sub_flag[2] <= 1'b1;
				end
			end

			if (expired_post_history_write_back_delay == 1'b1)
				expPostHist <= 1'b0;
			

			//shift_writeback_en_buffer_i_dealy1 <= shift_writeback_en_buffer_i;
			//shift_writeback_en_buffer_i_dealy2 <= shift_writeback_en_buffer_i_dealy1;

			add_sub_flag[1] <= add_sub_flag[2];
			add_sub_flag[0] <= add_sub_flag[1];

			//if (shift_writeback_en_buffer_i_dealy2 == 1'b1)
				weight_writeback_enable_buffer <= {weight_writeback_enable_buffer[2:0], update_weight_enable}; 

			//delay generated spike by two clocks for LTP/LTD condition
			lrnOutSpikeReg_delay[1] <= lrnOutSpikeReg;
			lrnOutSpikeReg_delay[0] <= lrnOutSpikeReg_delay[1];
			

			delta_WtBias <= delta_WtBias_Th;
			if (add_sub_flag[0] == 1'b0)
				quant_Dlta_Wt_Bias_reg <= quant_Dlta_Wt_Bias;
			else
				quant_Dlta_Wt_Bias_reg <= (~quant_Dlta_Wt_Bias) + 1;

			//if (expPostHist == 1'b1)
			//	en_expired_post_history_write_back <= 1'b1;
			//else
			//	en_expired_post_history_write_back <= 1'b0;

			// if (expired_post_history_write_back_i == 1'b1)
			// 	en_expired_post_history_write_back <= 1'b0;
			// else if ( expPostHist == 1'b1)
			// 	en_expired_post_history_write_back <= 1'b1;
			// else
			// 	en_expired_post_history_write_back <= en_expired_post_history_write_back;

			// if (expPreHist == 1'b1) begin
			// 	PreSpikeHist_Ppln[3] <= LTP_Win_i + 1;
			// end else if (axonLrnMode_i == 1'b1) begin
			// 	PreSpikeHist_Ppln[4] <= preSpikeHist;	
			// end
			// //bug: PreSpikeHist_Ppln[3] multiplle drive
			// for(i = 0; i < 4; i = i + 1)
			// 	PreSpikeHist_Ppln[i] <= PreSpikeHist_Ppln[i+1];
			

			//fix:
			if (expPreHist == 1'b1) 
				begin
					PreSpikeHist_Ppln[3] <= LTP_Win_i + 1;
					PreSpikeHist_Ppln[4] <= preSpikeHist;
					//PreSpikeHist_Ppln[4] <= ?????
				end
			else //if (axonLrnMode_i == 1'b1) 
				begin
					PreSpikeHist_Ppln[4] <= preSpikeHist;
					PreSpikeHist_Ppln[3] <= PreSpikeHist_Ppln[4];
				end
		
			PreSpikeHist_Ppln[0] <= PreSpikeHist_Ppln[1];
			PreSpikeHist_Ppln[1] <= PreSpikeHist_Ppln[2];
			PreSpikeHist_Ppln[2] <= PreSpikeHist_Ppln[3];

			bufBias_delay[1] <= bufBias;
			bufBias_delay[0] <= bufBias_delay[1];


			lrnUseBias_dly <= lrnUseBias_i;
			if (lrnUseBias_dly == 1'b1) begin
				WeightBias_Ppln[2] <= bufBias_delay[0];
			end else begin
				WeightBias_Ppln[2] <= data_StatRd_F_i;
			end
			for(i = 0; i < 2; i = i + 1)
				WeightBias_Ppln[i] <= WeightBias_Ppln[i+1];
			updtReg_WeightBias <= updt_WeightBias;

			enLrn_Ppln <= {axonLrnMode_i,enLrn_Ppln[4:1]};

			shiftRight_dly <= shiftRight;
		end
	end

assign en_expired_post_history_write_back_o = expPostHist;
assign update_weight_enable_o = weight_writeback_enable_buffer[3];

	//MODULE INSTANTIATIONS
	//--------------------------------------------------//
	Adder_2sComp
	#(
		.DSIZE    ( DSIZE )
	)
	RECALL_ADDER
	(
		.A_din_i		( rclAdd_A ),
		.B_din_i		( rclAdd_B ),
		.twos_cmplmnt_i	( 1'b1 ),
		
		.clipped_sum_o	( accIn ),
		.sum_o			(  ),
		.carry_o 		(  ),
		.overflow_o 	(  ),
		.underflow_o 	(  )
	);

	Adder_2sComp
	#(
		.DSIZE    ( DSIZE )
	)
	DELTA_WT_BIAS_ADDER
	(
		.A_din_i		( deltaAdder_inA 	),
		.B_din_i		( deltaAdder_inB 	),
		.twos_cmplmnt_i	( deltaAdder_signed	),
		
		.clipped_sum_o	( delta_WtBias_Th ),
		.sum_o			(  ),
		.carry_o 		(  ),
		.overflow_o 	(  ),
		.underflow_o 	(  )
	);

	Adder_2sComp
	#(
		.DSIZE    ( DSIZE )
	)
	UPDATE_WT_BIAS_ADDER
	(
		.A_din_i		( WeightBias_Ppln[0] ),
		.B_din_i		( quant_Dlta_Wt_Bias_reg ),
		.twos_cmplmnt_i	( 1'b1 			),
		
		.clipped_sum_o	( updt_WeightBias ),
		.sum_o			(  ),
		.carry_o 		(  ),
		.overflow_o 	(  ),
		.underflow_o 	(  )
	);

	Lfsr 
	#(
		.DSIZE    ( DSIZE ),
		.SEED     ( SEED  )
	) 
	RAND_NUM
	(
		.clk_i		( clk_i			),
		.reset_n_i	( rst_n_i 		),
	
		.rd_rand_i	( rdLFSR_dly[0] & outSpike_o),
		.lfsr_dat_o ( lfsr_data 	)
	);

	PriorityEncoder
	#(
		.IN_DSIZE	( DATA_BIT_WIDTH_INT-1		),
		.OUT_DSIZE	( PRIORITY_ENC_OUT_BIT_WIDTH)
	)
	ENCODER
	(
		.in_data_i 		( pEnc_in 	), 

		.valid_bit_o 	( 	), 
		.out_data_o 	( pEnc_out 	)
	);

	barrel_shifter
	#(	
		.DSIZE		( DSIZE ),
		.SHIFTSIZE	( PRIORITY_ENC_OUT_BIT_WIDTH )
	)
	SHIFTER
	(
		.shift_in 		( {shifter_in_int,shifter_in_frac} ),
		.rightshift_i 	( shiftRight_dly ),
		.shift_by_i 	( quantVal ),

		.shift_out_o	( quant_Dlta_Wt_Bias )
	);

Signed_Comparator
#(.DSIZE(DSIZE))
Comparator
// (.A_din_i(AccReg), .B_din_i(data_StatRd_A_i), .equal(threshold_equal), .lower(), .greater(threshold_greater));
(.A_din_i(AccReg), .B_din_i(data_rd_threshold_i), .equal(threshold_equal), .lower(), .greater(threshold_greater));

`ifdef DUMP_OUTPUT_SPIKE

integer step_counter = 0;

always @(posedge clk_i)
	if(start_i == 1'b1)
		step_counter = step_counter + 1;

integer f, k;
reg [100*8:1] file_name;

initial
	begin
	file_name = {SIM_PATH, "data", DIR_ID, "/dump_output_spike.csv"};
		f = $fopen(file_name, "w");

		//write header
		$fwrite(f, "neuron_id,");

		for (k = 0; k < NUM_NURNS; k = k + 1)
			begin
				$fwrite(f, "%0d,", k);			//neuron id
			end	
		//$fwrite(f, "\n");
	end

//record spikes
always @(posedge clk_i)
	begin
		if(step_counter < STOP_STEP)
			begin
				if (start_i == 1'b1)
					begin
						$fwrite(f, "\n");
						$fwrite(f, "step-%0d,",step_counter);
					end

				if(cmp_th_i == 1'b1)
					$fwrite(f, "%b,", comp_out);
			end
		else
			$fclose(f);
	end

`endif


endmodule