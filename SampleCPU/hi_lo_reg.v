`include "lib/defines.vh" 
module hi_lo_reg(
    input wire clk, // 时钟信号
    // input wire rst,// 重置信号（当前未使用）
    input wire [`StallBus-1:0] stall, // 停顿信号总线，用于控制流水线停顿
    input wire hi_we, // HI寄存器写使能信号
    input wire lo_we, // LO寄存器写使能信号
    input wire [31:0] hi_wdata, // HI寄存器写入数据
    input wire [31:0] lo_wdata, // LO寄存器写入数据
    output wire [31:0] hi_rdata, // HI寄存器读出数据
    output wire [31:0] lo_rdata // LO寄存器读出数据
);

    // 内部寄存器，保存HI和LO的当前值
    reg [31:0] reg_hi;
    reg [31:0] reg_lo;

    // 时钟上升沿时更新HI和LO寄存器的值
    always @ (posedge clk) begin
        // 如果同时使能HI和LO寄存器的写操作
        if (hi_we & lo_we) begin
            reg_hi <= hi_wdata; // 更新HI寄存器
            reg_lo <= lo_wdata; // 更新LO寄存器
        end
        // 如果仅使能LO寄存器的写操作
        else if (~hi_we & lo_we) begin
            reg_lo <= lo_wdata; // 更新LO寄存器
        end
        // 如果仅使能HI寄存器的写操作
        else if (hi_we & ~lo_we) begin
            reg_hi <= hi_wdata; // 更新HI寄存器
        end
        // 如果既不使能HI也不使能LO，则保持当前值
    end

    // 将HI和LO寄存器的当前值输出
    assign hi_rdata = reg_hi;
    assign lo_rdata = reg_lo;

endmodule
