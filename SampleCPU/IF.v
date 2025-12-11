`include "lib/defines.vh"

// 从内存中取指令
// 使用PC中的地址，从存储器中读取数据，然后将数据放入IF/ID流水线寄存器中。
// PC地址+4然后写回PC以便为下个时钟周期做好准备，
// 增加后的地址同时也存入了IF/ID流水线寄存器以备后面的指令使用。
//
// 新指令一般对齐没有影响（除了在添加异常的时候，需要检查指令地址是否出错）
// 在P64之前注意跳转指令即可

module IF(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号，高电平有效
    input wire [`StallBus-1:0] stall,  // 停顿信号总线，用于控制流水线的暂停

    // input wire flush,  // 流水线冲刷信号（当前未使用）
    // input wire [31:0] new_pc,  // 新的PC值，用于跳转（当前未使用）

    input wire [`BR_WD-1:0] br_bus,  // 来自分支预测单元的分支信息，总线宽度为`BR_WD`

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 传递给ID阶段的数据总线，包含使能信号和当前PC值

    output wire inst_sram_en,  // 指令存储器使能信号，控制是否进行读操作
    output wire [3:0] inst_sram_wen,  // 指令存储器写使能信号（固定为0，表示不进行写操作）
    output wire [31:0] inst_sram_addr,  // 指令存储器地址，根据当前PC值生成
    output wire [31:0] inst_sram_wdata  // 指令存储器写数据（固定为0，表示不进行写操作）
);

    // 内部寄存器，保存当前的程序计数器（PC）值
    reg [31:0] pc_reg;  // 程序计数器寄存器
    reg ce_reg;          // 指令存储器使能寄存器

    // 中间信号，用于计算下一个PC值和解析分支信息
    wire [31:0] next_pc;  // 计算出的下一个程序计数器值
    wire br_e;            // 分支是否有效标志
    wire [31:0] br_addr;  // 分支目标地址

    // 从分支信息总线`br_bus`中解码出分支有效标志`br_e`和分支地址`br_addr`
    assign { br_e, br_addr } = br_bus;

    // 时序逻辑：更新程序计数器`pc_reg`
    always @ (posedge clk) begin
        if (rst) begin
            pc_reg <= 32'hbfbf_fffc;  // 复位时，将程序计数器设置为特定的初始地址
        end
        else if (stall[0] == `NoStop) begin
            pc_reg <= next_pc;  // 如果没有停顿信号，则更新程序计数器为下一个PC值
        end
        // 否则保持当前PC值（流水线暂停）
    end

    // 时序逻辑：更新指令存储器使能信号`ce_reg`
    always @ (posedge clk) begin
        if (rst) begin
            ce_reg <= 1'b0;  // 复位时，禁用指令存储器
        end
        else if (stall[0] == `NoStop) begin
            ce_reg <= 1'b1;  // 如果没有停顿信号，则启用指令存储器
        end
        // 否则保持当前使能状态（通常保持为1）
    end

    // 计算下一个程序计数器值
    // 如果分支有效（`br_e`为1），则跳转到分支地址`br_addr`
    // 否则，顺序执行下一条指令（PC + 4）
    assign next_pc = br_e ? br_addr
                   : pc_reg + 32'h4;

    // 指令存储器接口信号分配
    assign inst_sram_en = ce_reg;          // 根据使能寄存器决定是否启用指令存储器
    assign inst_sram_wen = 4'b0;          // 不进行写操作，因此写使能信号固定为0
    assign inst_sram_addr = pc_reg;        // 指令存储器地址由当前PC值决定
    assign inst_sram_wdata = 32'b0;        // 没有写入数据，固定为0

    // 将指令存储器使能信号和当前PC值打包传递给ID阶段
    assign if_to_id_bus = {
        ce_reg,    // 指令存储器使能信号，高位
        pc_reg     // 当前程序计数器值，低位
    };

endmodule
