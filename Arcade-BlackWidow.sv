
module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S    // 1 - signed audio samples, 0 - unsigned
);

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;


`include "build_id.v" 
localparam CONF_STR = {
	"A.BWIDOW;;",
	"F,rom;", // allow loading of alternate ROMs
	"-;",
	"O1,Aspect Ratio,Original,Wide;",
//	"O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",  
	"-;",
	"O89,Max Start Level,13,21,37,53;",
	"OAB,Lives,3,4,5,6;",
	"ODE,Difficulty,Easy,Medium,Hard,Demo;",
	"OFG,Extra Spider,20k,30k,40k,None;",
	"-;",
	"O7,Test,Off,On;",
	"-;",
	"R0,Reset;",
	"J1,Fire Right,Fire Left,Fire Down,Fire Up,Start 1, Start 2;",
	"V,v2.00.",`BUILD_DATE
};


wire [7:0] sw_d4 = {2'b00, 2'b00,1'b0,3'b000}; // coins
//wire [7:0] sw_b4 = { status[9:8],status[11:10],status[14:13],status[16:15]};
wire [7:0] sw_b4 = {status[16:15],status[14:13],status[11:10], status[9:8]};

/*
-------------------------------------------------------------------------------
Settings of 8-Toggle Switch on Black Widow CPU PCB (at D4)
 8   7   6   5   4   3   2   1   Option
-------------------------------------------------------------------------------
Off Off                          1 coin/1 credit <
On  On                           1 coin/2 credits
On  Off                          2 coins/1 credit
Off On                           Free play

        Off Off                  Right coin mechanism x 1 <
        On  Off                  Right coin mechanism x 4
        Off On                   Right coin mechanism x 5
        On  On                   Right coin mechanism x 6

                Off              Left coin mechanism x 1 <
                On               Left coin mechanism x 2

                    Off Off Off  No bonus coins (0)* <
                    Off On  On   No bonus coins (6)
                    On  On  On   No bonus coins (7)

                    On  Off Off  For every 2 coins inserted,
                                 logic adds 1 more coin (1)
                    Off On  Off  For every 4 coins inserted,
                                 logic adds 1 more coin (2)
                    On  On  Off  For every 4 coins inserted,
                                 logic adds 2 more coins (3)
                    Off Off On   For every 5 coins inserted,
                                 logic adds 1 more coin (4)
                    On  Off On   For every 3 coins inserted,
                                 logic adds 1 more coin (5)

-------------------------------------------------------------------------------

* The numbers in parentheses will appear on the BONUS ADDER line in the
  Operator Information Display (Figure 2-1) for these settings.
< Manufacturer's recommended setting


                Table 1-3  Switch Settings for Special Options

-------------------------------------------------------------------------------
Settings of 4-Toggle Switch on Black Widow CPU PCB (at P10/11)
 4   3   2   1                   Option
-------------------------------------------------------------------------------
            On                   Credits counted on one coin counter
            Off                  Credits counted on two separate coin counters
-------------------------------------------------------------------------------


          Table 1-4  Switch Settings for Bonus and Difficulty Options

-------------------------------------------------------------------------------
Settings of 8-Toggle Switch on Black Widow CPU PCB (at B4)
 8   7   6   5   4   3   2   1   Option
-------------------------------------------------------------------------------
Off Off                          Maximum start at level 13
On  Off                          Maximum start at level 21 <
Off On                           Maximum start at level 37
On  On                           Maximum start at level 53

        Off Off                  3 spiders per game <
        On  Off                  4 spiders per game
        Off On                   5 spiders per game
        On  On                   6 spiders per game

                Off Off          Easy game play
                On  Off          Medium game play <
                Off On           Hard game play
                On  On           Demonstration mode

                        Off Off  Bonus spider every 20,000 points <
                        On  Off  Bonus spider every 30,000 points
                        Off On   Bonus spider every 40,000 points
                        On  On   No bonus

*/

////////////////////   CLOCKS   ///////////////////

wire clk_6, clk_12,clk_25,clk_24;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_6),	
	.outclk_1(clk_25),	
	.outclk_2(clk_24),	
	.outclk_3(clk_12),	
	.locked(pll_locked)
);


///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joy_0, joy_1;
wire [15:0] joy = joy_0 | joy_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_25),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joy_0),
	.joystick_1(joy_1),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_25) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right

			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2
			
			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			
			'hX2C: btn_test       <= pressed; // T

		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;
reg btn_test=0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;

wire m_up     =  btn_up    | joy[3];
wire m_down   =  btn_down  | joy[2];
wire m_left   =  btn_left  | joy[1];
wire m_right  =  btn_right | joy[0];


wire m_fire_up     = btn_up_2    | joy[6];
wire m_fire_down   = btn_down_2  | joy[7];
wire m_fire_left   = btn_left_2  | joy[5];
wire m_fire_right  = btn_right_2 | joy[4];

wire m_start1 = btn_one_player  | joy[8];
wire m_start2 = btn_two_players  | joy[9];
wire m_coin   = m_start1 | m_start2 ;


//buttons(14 downto 0): SELFTEST, SA, COINAUX COINL COINR START2 START1 FD FU FL FR MU MD ML MR

//wire [14:0] BUTTONS = {status[7],1'b0,~(btn_coin_1|m_coin|btn_coin_2),1'b1,1'b1,~(btn_two_players|btn_start_2) ,~(btn_one_player|btn_start_1) & ~joy[7],m_down,m_up,m_left,m_right,m_up_2,m_down_2,m_left_2,m_right_2};
wire [14:0] BUTTONS = {btn_test,~status[7],
                       ~(btn_coin_1|m_coin),~btn_coin_2,1'b0,
							  ~(btn_two_players|btn_start_2) ,~(btn_one_player|btn_start_1) ,
							  ~m_fire_down,~m_fire_up,~m_fire_left,~m_fire_right,
							  ~m_up,~m_down,~m_left,~m_right};
wire hblank, vblank;
/*
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

reg ce_pix;
always @(posedge clk_24) begin
        reg old_clk;

        old_clk <= clk_6;
        ce_pix <= old_clk & ~clk_6;
end

arcade_fx #(640,9) arcade_video
(
        .*,

        .clk_video(clk_24),

        .RGB_in({r,g,b}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(~hs),
        .VSync(~vs),

        .fx(status[5:3])
);
*/
wire ce_vid = 1; 
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

assign VGA_CLK  = clk_25; 
assign VGA_CE   = ce_vid;
assign VGA_R    = {r,r,r[2:1]};
assign VGA_G    = {g,g,g[2:1]};
assign VGA_B    = {b,b,b[2:1]};
assign VGA_HS   = ~hs;
assign VGA_VS   = ~vs;
assign VGA_DE   = vgade;

assign HDMI_CLK = VGA_CLK;
assign HDMI_CE  = VGA_CE;
assign HDMI_R   = VGA_R ;
assign HDMI_G   = VGA_G ;
assign HDMI_B   = VGA_B ;
assign HDMI_DE  = VGA_DE;
assign HDMI_HS  = VGA_HS;
assign HDMI_VS  = VGA_VS;
//assign HDMI_SL  = status[2] ? 2'd0   : status[4:3];
assign HDMI_SL  = 2'd0;


wire reset = (RESET | status[0] |  buttons[1] | ioctl_download);
wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
wire [1:0] lang = 2'b00;
wire [1:0] ships = 2'b00;
wire vgade;

ASTEROIDS_TOP ASTEROIDS_TOP
(

	.BUTTON(BUTTONS),
	.SELF_TEST_SWITCH_L(~status[7]), 
	.LANG(lang),
	.SHIPS(ships),
	.AUDIO_OUT(audio),
	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr),	
	.VIDEO_R_OUT(r),
	.VIDEO_G_OUT(g),
	.VIDEO_B_OUT(b),
	.HSYNC_OUT(hs),
	.VSYNC_OUT(vs),
	.VGA_DE(vgade),
	.VID_HBLANK(hblank),
	.VID_VBLANK(vblank),

	.SW_B4(sw_b4),
	.SW_D4(sw_d4),
	
	.RESET_L (~reset),	
	.clk_6(clk_6),
	.clk_12(clk_12),
	.clk_25(clk_25)
);

endmodule
