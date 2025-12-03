`include "lib/defines.vh"  // 引入定义文件，包含各种宏定义和参数

// hi和lo属于协处理器，不在通用寄存器的范围内。
// 这两个寄存器主要是在用来处理乘法和除法。
// 以乘法作为示例，如果两个整数相乘，那么乘法的结果低位保存在lo寄存器，高位保存在hi寄存器。
// 当然，这两个寄存器也可以独立进行读取和写入。读的时候，使用mfhi、mflo；写入的时候，用mthi、mtlo。
// 和通用寄存器不同，mfhi、mflo是在执行阶段才开始从hi、lo寄存器获取数值的。写入则和通用寄存器一样，也是在写回的时候完成的。

module hi_lo_reg(
    input wire clk,                  // 时钟信号
    // input wire rst,               // 重置信号（当前未使用）
    input wire [`StallBus-1:0] stall, // 停顿信号总线，用于控制流水线停顿

    input wire hi_we,                // HI寄存器写使能信号
    input wire lo_we,                // LO寄存器写使能信号

    input wire [31:0] hi_wdata,      // HI寄存器写入数据
    input wire [31:0] lo_wdata,      // LO寄存器写入数据

    output wire [31:0] hi_rdata,     // HI寄存器读出数据
    output wire [31:0] lo_rdata      // LO寄存器读出数据
);

    // 内部寄存器，保存HI和LO的当前值
    reg [31:0] reg_hi;
    reg [31:0] reg_lo;

    // 时钟上升沿时更新HI和LO寄存器的值
    always @ (posedge clk) begin
        // 如果同时使能HI和LO寄存器的写操作
        if (hi_we & lo_we) begin
            reg_hi <= hi_wdata;  // 更新HI寄存器
            reg_lo <= lo_wdata;  // 更新LO寄存器
        end
        // 如果仅使能LO寄存器的写操作
        else if (~hi_we & lo_we) begin
            reg_lo <= lo_wdata;  // 更新LO寄存器
        end
        // 如果仅使能HI寄存器的写操作
        else if (hi_we & ~lo_we) begin
            reg_hi <= hi_wdata;  // 更新HI寄存器
        end
        // 如果既不使能HI也不使能LO，则保持当前值
    end

    // 将HI和LO寄存器的当前值输出
    assign hi_rdata = reg_hi;
    assign lo_rdata = reg_lo;

    // 以下是注释掉的复位逻辑（如果需要可以启用）
    /*
    always @ (posedge clk) begin
        if (rst) begin
            reg_hi <= 32'b0;    // 复位时，将HI寄存器清零
            reg_lo <= 32'b0;    // 复位时，将LO寄存器清零
        end
        else if (wb_lo_we) begin
            reg_hi <= wb_hi_in;   // 从写回阶段接收HI寄存器写入数据
            reg_lo <= wb_lo_in;   // 从写回阶段接收LO寄存器写入数据
        end
    end
    */

endmodule
