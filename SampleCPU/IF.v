`include "lib/defines.vh" 

// 从内存中取指令
// 使用PC中的地址，从存储器中读取数据，然后将数据放入IF/ID流水线寄存器中。
// PC地址+4然后写回PC以便为下个时钟周期做好准备，
// 增加后的地址同时也存入了IF/ID流水线寄存器以备后面的指令使用。

// 新指令一般对其没有影响（除了在添加异常的时候，需要检查指令地址是否出错）
// P64之前注意跳转指令即可

module IF(
    input wire clk,  // 时钟信号
    input wire rst,  // 重置信号
    input wire [`StallBus-1:0] stall,  // 停顿信号，用于控制流水线停顿
    input wire [`BR_WD-1:0] br_bus,  // 来自分支预测模块的分支信息

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 传递给ID阶段的数据
    output wire inst_sram_en,  // 指令存储器使能信号
    output wire [3:0] inst_sram_wen,  // 指令存储器写使能信号
    output wire [31:0] inst_sram_addr,  // 指令存储器地址
    output wire [31:0] inst_sram_wdata  // 指令存储器写数据
);

    // 内部寄存器，保存当前的程序计数器（PC）值
    reg [31:0] pc_reg;
    reg ce_reg;  // 存储指令存储器是否启用的控制信号
    wire [31:0] next_pc;  // 计算出的下一个程序计数器值
    wire br_e;  // 分支是否有效
    wire [31:0] br_addr;  // 分支目标地址

    // 从br_bus中解析出分支信息 br_e（分支有效标志）和 br_addr（分支地址）
    assign { br_e, br_addr } = br_bus;

    // 在时钟上升沿时更新pc_reg（程序计数器）
    always @ (posedge clk) begin
        if (rst) begin
            pc_reg <= 32'hbfbf_fffc;  // 复位时，将程序计数器设置为一个特定值
        end
        else if (stall[0]==`NoStop) begin  // 如果没有停顿信号，则更新pc_reg为next_pc
            pc_reg <= next_pc;
        end
    end

    // 在时钟上升沿时更新ce_reg（指令存储器启用信号）
    always @ (posedge clk) begin
        if (rst) begin
            ce_reg <= 1'b0;  // 复位时禁用指令存储器
        end
        else if (stall[0]==`NoStop) begin  // 如果没有停顿信号，则启用指令存储器
            ce_reg <= 1'b1;
        end
    end

    // 计算下一个程序计数器值，如果有分支（br_e为1），则跳转到分支地址，否则PC+4
    assign next_pc = br_e ? br_addr : pc_reg + 32'h4;

    // 指令存储器相关信号
    assign inst_sram_en = ce_reg;  // 启用指令存储器
    assign inst_sram_wen = 4'b0;  // 不进行写操作，因此写使能为0
    assign inst_sram_addr = pc_reg;  // 指令存储器地址为当前的PC值
    assign inst_sram_wdata = 32'b0;  // 没有写入数据

    // 将ce_reg和pc_reg传递给ID阶段
    assign if_to_id_bus = { ce_reg, pc_reg };

endmodule