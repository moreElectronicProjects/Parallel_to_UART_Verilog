`timescale 1ns / 1ps

module parallel_to_UART(
    input reset, //Active high reset
    input clock, //Input clock signal
    input [7:0] data, //Data to send
    input data_ready, //Indication the data is ready to send
    output serial_out, //The output serial connection
    output ready //Indicates the module is ready to accept data to send
    );

    //The speed of the input clock (in kHz).  Must be at least twice the speed
    //of the baud rate.
    parameter input_clock_frequency = 100000;

    //The output serial baud rate.
    parameter baud_rate = 115200;

    //The internal clock needs to run at twice the baud rate frequency  Due to
    //the clock divider, there is a divide by two.  As a result, they cancel
    //each other out.
    localparam clock_divider_max_counter = input_clock_frequency * 1000 / baud_rate;

    //The clock to used to generate the final serial output.
    wire internal_clock;

    //Generates the clock which drives the serial output.
    clock_divider # (
        .max_counter (clock_divider_max_counter)
    ) serial_clock (
        .reset(reset),
        .input_clock(clock),
        .output_clock(internal_clock)
    );

    //Indicates when the circuit is not sending any data.
    wire done_sending;

    //Stores which bit of the serial output is going to be sent.
    wire [3:0] bit_to_send;

    //Holds the data once it is latched in.
    wire [7:0] latched_data;

    //Allows sending the serial data.
    wire counter_enable;

    assign ready = !counter_enable;

    //SR latch to make sure the data does not change as the serial data is
    //being sent out.
    SR_latch latch_data (
        .set(data_ready),
        .reset(done_sending | reset),
        .Q(counter_enable)
    );

    //Data input latch.
    data_latch data_latch_circuit(
        .clock(data_ready),
        .reset(reset),
        .enable(!counter_enable),
        .data_input(data),
        .data_output(latched_data)
    );

    //The done sending signal needs to be high when bit_to_send is
    //equal to 11.
    assign done_sending = (bit_to_send == 'd11);

    //The binary count which keeps track of which data bit to send.
    binary_counter_4_bit bit_to_send_counter(
        .reset(reset | done_sending),
        .clock(internal_clock),
        .enable(counter_enable),
        .count(bit_to_send)
    );

    //Mux to select which bit to send.
    mux_4_bit data_out_mux(
        .data_input_0(1'b1),
        .data_input_1(1'b0),
        .data_input_2(data[0]),
        .data_input_3(data[1]),
        .data_input_4(data[2]),
        .data_input_5(data[3]),
        .data_input_6(data[4]),
        .data_input_7(data[5]),
        .data_input_8(data[6]),
        .data_input_9(data[7]),
        .data_input_10(1'b1),
        .data_input_11(1'b1),
        .select(bit_to_send),
        .mux_output(serial_out)
    );
endmodule

//Define the 4 bit mux.  Only 12 inputs are defined.  If select is greater
//than 11, the output is 0.
module mux_4_bit(
    //The data inputs.  Not define all 16 inputs as the circuit only requires
    //12 inputs.  This is to simplify the code.
    input data_input_0,
    input data_input_1,
    input data_input_2,
    input data_input_3,
    input data_input_4,
    input data_input_5,
    input data_input_6,
    input data_input_7,
    input data_input_8,
    input data_input_9,
    input data_input_10,
    input data_input_11,
    input [3:0] select, //Indicates which input gets transfer to the output.
    output reg mux_output //Output from the mux.
    );

    //Select the correct input to be transfer to the output.
    always @ (*) begin
        case(select)
            'd0 : mux_output <= data_input_0;
            'd1 : mux_output <= data_input_1;
            'd2 : mux_output <= data_input_2;
            'd3 : mux_output <= data_input_3;
            'd4 : mux_output <= data_input_4;
            'd5 : mux_output <= data_input_5;
            'd6 : mux_output <= data_input_6;
            'd7 : mux_output <= data_input_7;
            'd8 : mux_output <= data_input_8;
            'd9 : mux_output <= data_input_9;
            'd10 : mux_output <= data_input_10;
            'd11 : mux_output <= data_input_11;
            default: mux_output <= 'b0;
        endcase
    end
endmodule

//4 bit binary counter with enable.
module binary_counter_4_bit(
    input reset, //Reset the counter when high
    input clock, //Increment the count on each rising edge
    input enable, //Enable the count
    output reg [3:0] count //The current count value.
    );

    always @ (posedge clock or posedge reset) begin
        //Reset the counter if reset is high
        if(reset == 'b1) begin
            count <= 'b0;
        //If the enable line is high, increment the count.
        end else if(enable == 'b1) begin
            count <= count + 'b1;
        end
    end
endmodule

module SR_latch(
    input set, //Sets Q to 1 when high
    input reset, //Sets Q to 0 when high
    output reg Q //The output value
    );

    always @ (posedge set or posedge reset) begin
        if(set == 'b1) begin
            Q <= 'b1;
        end else begin
            Q <= 'b0;
        end
    end
endmodule

module data_latch(
    input clock, //If enable is high, the data on the input is latched into the output on the rising edge.
    input reset, //Set the data output to 0 when high
    input enable, //Allows the input data to be transferred to the output on the next rising edge of clock.
    input [7:0] data_input, //The 8 bit data input
    output reg [7:0] data_output //The latched 8 bit data output
    );

    always @ (posedge clock or posedge reset) begin
        if(reset == 'b1) begin
            data_output <= 'b0;
        end else if(enable == 'b1) begin
            data_output <= data_input;
        end
    end
endmodule

//Divides the input clock down.
module clock_divider(
    input reset, //Reset the counter
    input input_clock, //The clock to be divided down
    output reg output_clock //The divided clock
    );

    //Define the number of rising edges it takes the input clock to create one
    //period for the output clock.  At half this value, the output clock goes
    //high.  At this value, the output clock goes low.
    parameter max_counter = 0;

    // Value to keep track of the count.
    reg [$clog2(max_counter):0] clock_divider;

    //Binary counter.  When the counter reaches half max_count, set the output
    //high.  When the counter reaches max_count, set the output low and reset
    //the counter.
    always @ (posedge input_clock or posedge reset) begin
        if(reset == 'b1) begin
            clock_divider <= 'b0;
            output_clock <= 'b0;
        end else begin
            clock_divider <= clock_divider + 'b1;
            if(clock_divider == max_counter/2) begin
                output_clock <= 'b1;
            end else if(clock_divider == max_counter) begin
                output_clock <= 'b0;
                clock_divider <= 'b0;
            end
        end
    end
endmodule
