`include "lib/defines.vh"
module CTRL(
    input wire rst,

    input wire stallreq_for_ex,
    input wire stallreq_for_bru,
    input wire stallreq_for_load,

    // output reg flush,
    // output reg [31:0] new_pc,
    output reg [`StallBus-1:0] stall
);
    // stall[0]表示取指地址PC是否保持不变，为1表示保持不变。
    // stall[1]表示流水线取指阶段是否暂停，为1表示暂停。
    // stall[2]表示流水线译码阶段是否暂停，为1表示暂停。
    // stall[3]表示流水线执行阶段是否暂停，为1表示暂停。
    // stall[4]表示流水线访存阶段是否暂停，为1表示暂停。
    // stall[5]表示流水线回写阶段是否暂停，为1表示暂停。


    always @ (*) begin
        if (rst) begin
            stall = `StallBus'b0;
        end
        //todo: stallreq_for_ex, stallreq_for_bru, stallreq_for_load
        //还没写完，加上后过不了1号测试点
        else if (stallreq_for_ex) begin
            stall = `StallBus'b001111;
        end
        //
        else if (stallreq_for_bru) begin
            stall = `StallBus'b000111;
        end

        // else if (stallreq_for_load) begin
        //     stall = `StallBus'b000011;
        // end

        else begin
            stall = `StallBus'b0;
        end
    end

endmodule