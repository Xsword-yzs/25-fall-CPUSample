`include "lib/defines.vh"  // 引入定义文件，包含各种宏定义和参数

// 将结果写回寄存器
// 从MEM/WB流水线寄存器中读取数据并将它写回寄存器堆中。
// 和IF段类似，暂时没有需要改动的东西

module WB(
    input wire clk,  // 时钟信号
    input wire rst,  // 重置信号，高电平有效
    // input wire flush,  // 流水线冲刷信号（当前未使用）
    input wire [`StallBus-1:0] stall,  // 停顿信号总线，用于控制流水线的暂停

    input wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus,  // 从MEM阶段传递到WB阶段的数据总线

    output wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 从WB阶段传递到寄存器文件的数据总线

    output wire [31:0] debug_wb_pc,       // 调试用：写回阶段的PC
    output wire [3:0] debug_wb_rf_wen,    // 调试用：寄存器写使能信号
    output wire [4:0] debug_wb_rf_wnum,   // 调试用：寄存器写地址
    output wire [31:0] debug_wb_rf_wdata  // 调试用：寄存器写数据
);

    // 暂存来自MEM阶段的数据总线
    reg [`MEM_TO_WB_WD-1:0] mem_to_wb_bus_r;

    // 时钟上升沿时更新寄存器的值
    always @ (posedge clk) begin
        if (rst) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;  // 复位时清空数据总线寄存器
        end
        // else if (flush) begin
        //     mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;  // 如果收到冲刷信号，清空数据总线寄存器（当前未使用）
        // end
        else if (stall[4] == `Stop && stall[5] == `NoStop) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;  // 当WB阶段停顿且下一阶段不停顿时，清空寄存器
        end
        else if (stall[4] == `NoStop) begin
            mem_to_wb_bus_r <= mem_to_wb_bus;    // 正常情况下，更新数据总线寄存器
        end
        // 否则保持当前寄存器值（流水线停顿）
    end

    // 解包MEM到WB的数据总线
    wire [31:0] wb_pc;      // 当前指令的PC
    wire rf_we;             // 寄存器文件写使能信号
    wire [4:0] rf_waddr;    // 寄存器文件写地址
    wire [31:0] rf_wdata;   // 寄存器文件写数据

    assign {
        wb_pc,         // 75:44 - 当前指令的PC
        rf_we,         // 43    - 寄存器文件写使能
        rf_waddr,      // 42:38 - 寄存器文件写地址
        rf_wdata       // 37:6  - 寄存器文件写数据
    } = mem_to_wb_bus_r;

    // 将写回信息打包传递给寄存器文件
    assign wb_to_rf_bus = {
        rf_we,         // 寄存器文件写使能
        rf_waddr,      // 寄存器文件写地址
        rf_wdata       // 寄存器文件写数据
    };

    // 调试信号输出
    assign debug_wb_pc = wb_pc;                  // 输出当前指令的PC
    assign debug_wb_rf_wen = {4{rf_we}};         // 寄存器写使能信号扩展为4位
    assign debug_wb_rf_wnum = rf_waddr;          // 输出寄存器写地址
    assign debug_wb_rf_wdata = rf_wdata;         // 输出寄存器写数据

endmodule
