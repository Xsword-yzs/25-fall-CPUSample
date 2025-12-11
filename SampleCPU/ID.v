`include "lib/defines.vh"  // 引入定义文件，包含各种宏定义和参数

// 指令解码，同时读取寄存器
// IF/ID阶段可能会取出经符号扩展为32位的立即数和两个从寄存器中读取的数，放入ID/EX流水线寄存器

// 需要在该级进行指令译码
// 从寄存器中读取需要的数据
// 完成数据相关处理
// 生成发给EX段的控制信号

module ID(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号，高电平有效
    // input wire flush,  // 流水线冲刷信号（当前未使用）
    input wire [`StallBus-1:0] stall,  // 停顿信号，用于控制流水线暂停

    output wire stallreq,  // 停顿请求信号，通知流水线暂停

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 从IF阶段到ID阶段的数据总线

    input wire [31:0] inst_sram_rdata,  // 从指令SRAM读取的指令数据

    input wire ex_id,  // EX阶段标识信号，用于转发相关操作

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 从WB阶段到寄存器文件的数据总线
    //
    input wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus,  // 从EX阶段到寄存器文件的数据总线
    //
    input wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus,  // 从MEM阶段到寄存器文件的数据总线

    input wire [65:0] ex_hi_lo_bus,  // 从EX阶段传递的HI/LO寄存器相关信号
    output wire [71:0] id_hi_lo_bus,  // ID阶段传递给EX阶段的HI/LO寄存器相关信号

    output wire [`LoadBus-1:0] id_load_bus,  // ID阶段传递的Load信号
    output wire [`SaveBus-1:0] id_save_bus,  // ID阶段传递的Save信号

    output wire stallreq_for_bru,  // 分支指令单元发出的停顿请求信号

    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,  // 从ID阶段到EX阶段的数据总线

    output wire [`BR_WD-1:0] br_bus  // 分支跳转相关的信号总线
);

    // 寄存器，用于暂存从IF阶段传递过来的数据总线
    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;  // 暂存IF到ID的数据总线
    wire [31:0] inst;  // 当前指令
    wire [31:0] id_pc;  // 当前指令的程序计数器(PC)
    wire ce;  // 使能信号
    reg  flag;  // 标志位，用于处理停顿请求
    reg [31:0] buf_inst;  // 缓存指令，用于处理停顿期间的指令

    // 来自WB阶段的写回信号
    wire wb_rf_we;  // 寄存器文件写使能信号
    wire [4:0] wb_rf_waddr;  // 寄存器文件写地址
    wire [31:0] wb_rf_wdata;  // 寄存器文件写数据

    // 来自EX阶段的写回信号
    wire ex_rf_we;  // 寄存器文件写使能信号
    wire [4:0] ex_rf_waddr;  // 寄存器文件写地址
    wire [31:0] ex_rf_wdata;  // 寄存器文件写数据

    // 来自MEM阶段的写回信号
    wire mem_rf_we;  // 寄存器文件写使能信号
    wire [4:0] mem_rf_waddr;  // 寄存器文件写地址
    wire [31:0] mem_rf_wdata;  // 寄存器文件写数据

    // 时钟上升沿时，更新寄存器的值
    always @ (posedge clk) begin
        if (rst) begin
            // 复位时，清空暂存寄存器和标志位
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
            flag <= 1'b0;
            buf_inst <= 32'b0;
        end
        // else if (flush) begin
        //     // 如果收到冲刷信号，清空寄存器（当前未启用）
        //     if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            // 当stall信号为停顿且后续不继续停顿时，清空暂存寄存器和标志位
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
            flag <= 1'b0;
        end
        else if (stall[1]==`NoStop) begin
            // 当stall信号不为停顿时，更新暂存寄存器并重置标志位
            if_to_id_bus_r <= if_to_id_bus;
            flag <= 1'b0;
        end
        else if (stall[1]==`Stop && stall[2]==`Stop && ~flag) begin
            // 当stall信号为停顿且后续也停顿，且标志位未置位时，设置标志位并缓存当前指令
            flag <= 1'b1;
            buf_inst <= inst_sram_rdata;
        end
    end

    // 根据使能信号和标志位选择当前指令
    assign inst = ce ? flag ? buf_inst : inst_sram_rdata : 32'b0;

    // 解码来自EX阶段的写回信号
    assign {
        ex_rf_we,
        ex_rf_waddr,
        ex_rf_wdata
    } = ex_to_rf_bus;

    // 解码来自MEM阶段的写回信号
    assign {
        mem_rf_we,
        mem_rf_waddr,
        mem_rf_wdata
    } = mem_to_rf_bus;

    // 解码来自IF阶段的数据总线，提取使能信号和PC
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;

    // 解码来自WB阶段的写回信号
    assign {
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    // 指令字段解码
    wire [5:0] opcode;  // 操作码
    wire [4:0] rs, rt, rd, sa;  // 寄存器字段和移位量
    wire [5:0] func;  // 功能码
    wire [15:0] imm;  // 立即数
    wire [25:0] instr_index;  // 指令索引
    wire [19:0] code;  // 代码字段
    wire [4:0] base;  // 基址寄存器
    wire [15:0] offset;  // 偏移量
    wire [2:0] sel;  // 选择信号

    wire [63:0] op_d, func_d;  // 操作码和功能码的解码结果
    wire [31:0] rs_d, rt_d, rd_d, sa_d;  // 寄存器字段和移位量的解码结果

    wire [2:0] sel_alu_src1;  // ALU源操作数1的选择信号
    wire [3:0] sel_alu_src2;  // ALU源操作数2的选择信号
    wire [11:0] alu_op;  // ALU操作码

    wire data_ram_en;  // 数据RAM使能信号
    wire [3:0] data_ram_wen;  // 数据RAM写使能信号

    wire rf_we;  // 寄存器文件写使能信号
    wire [4:0] rf_waddr;  // 寄存器文件写地址
    wire sel_rf_res;  // 寄存器文件结果选择信号
    wire [2:0] sel_rf_dst;  // 寄存器文件目标选择信号

    wire [31:0] rdata1, rdata2;  // 从寄存器文件读出的数据1和数据2
    wire [31:0] ndata1, ndata2;  // 处理后的数据1和数据2

// 数据相关
    // 数据转发逻辑，选择最新的数据写回寄存器
    assign ndata1 = ((ex_rf_we && rs == ex_rf_waddr) ? ex_rf_wdata : 32'b0) |
                   ((!(ex_rf_we && rs == ex_rf_waddr) && (mem_rf_we && rs == mem_rf_waddr)) ? mem_rf_wdata : 32'b0) |
                   ((!(ex_rf_we && rs == ex_rf_waddr) &&
                    !(mem_rf_we && rs == mem_rf_waddr) && (wb_rf_we && rs == wb_rf_waddr)) ? wb_rf_wdata : 32'b0) |
                   (((ex_rf_we && rs == ex_rf_waddr) || (mem_rf_we && rs == mem_rf_waddr) ||
                     (wb_rf_we && rs == wb_rf_waddr)) ? 32'b0 : rdata1);

    assign ndata2 = ((ex_rf_we && rt == ex_rf_waddr) ? ex_rf_wdata : 32'b0) |
                   ((!(ex_rf_we && rt == ex_rf_waddr) && (mem_rf_we && rt == mem_rf_waddr)) ? mem_rf_wdata : 32'b0) |
                   ((!(ex_rf_we && rt == ex_rf_waddr) &&
                     !(mem_rf_we && rt == mem_rf_waddr) && (wb_rf_we && rt == wb_rf_waddr)) ? wb_rf_wdata : 32'b0) |
                   (((ex_rf_we && rt == ex_rf_waddr) || (mem_rf_we && rt == mem_rf_waddr) ||
                     (wb_rf_we && rt == wb_rf_waddr)) ? 32'b0 : rdata2);

    // 实例化寄存器文件，读取源操作数
    regfile u_regfile(
        .clk    (clk),          // 时钟信号
        .raddr1 (rs),           // 寄存器文件读地址1
        .rdata1 (rdata1),       // 寄存器文件读数据1
        .raddr2 (rt),           // 寄存器文件读地址2
        .rdata2 (rdata2),       // 寄存器文件读数据2
        .we     (wb_rf_we),     // 寄存器文件写使能
        .waddr  (wb_rf_waddr),  // 寄存器文件写地址
        .wdata  (wb_rf_wdata)   // 寄存器文件写数据
    );

    // HI/LO寄存器相关信号
    wire [31:0] hi, hi_rdata;  // HI寄存器读数据
    wire [31:0] lo, lo_rdata;  // LO寄存器读数据
    wire hi_we;  // HI寄存器写使能
    wire lo_we;  // LO寄存器写使能
    wire [31:0] hi_wdata;  // HI寄存器写数据
    wire [31:0] lo_wdata;  // LO寄存器写数据

    // 解码来自EX阶段的HI/LO信号
    assign {
        hi_we,
        lo_we,
        hi_wdata,
        lo_wdata
    } = ex_hi_lo_bus;

    // 实例化HI/LO寄存器
    hi_lo_reg u_hi_lo_reg(
        .clk      (clk),         // 时钟信号
        .hi_we    (hi_we),       // HI寄存器写使能
        .lo_we    (lo_we),       // LO寄存器写使能
        .hi_wdata (hi_wdata),    // HI寄存器写数据
        .lo_wdata (lo_wdata),    // LO寄存器写数据
        .hi_rdata (hi_rdata),    // HI寄存器读数据
        .lo_rdata (lo_rdata)     // LO寄存器读数据
    );

    // 根据HI/LO写使能信号选择HI和LO的读数据
    assign hi = hi_we ? hi_wdata : hi_rdata;
    assign lo = lo_we ? lo_wdata : lo_rdata;

    // 指令字段解码
    assign opcode = inst[31:26];  // 操作码
    assign rs = inst[25:21];      // 源寄存器1
    assign rt = inst[20:16];      // 源寄存器2
    assign rd = inst[15:11];      // 目标寄存器
    assign sa = inst[10:6];       // 移位量
    assign func = inst[5:0];      // 功能码
    assign imm = inst[15:0];      // 立即数
    assign instr_index = inst[25:0];  // 指令索引
    assign code = inst[25:6];         // 代码字段
    assign base = inst[25:21];        // 基址寄存器
    assign offset = inst[15:0];       // 偏移量
    assign sel = inst[2:0];            // 选择信号

    // 解码器实例化，将操作码和功能码解码为独热码
    // 6-64译码器，将6位输入转换为64位独热码
    decoder_6_64 u0_decoder_6_64(
        .in  (opcode),  // 输入操作码
        .out (op_d)     // 输出独热码
    );

    // 6-64译码器，将功能码解码为独热码
    decoder_6_64 u1_decoder_6_64(
        .in  (func),    // 输入功能码
        .out (func_d)   // 输出独热码
    );

    // 5-32译码器，将寄存器字段解码为独热码
    decoder_5_32 u0_decoder_5_32(
        .in  (rs),      // 输入寄存器rs
        .out (rs_d)     // 输出独热码
    );

    decoder_5_32 u1_decoder_5_32(
        .in  (rt),      // 输入寄存器rt
        .out (rt_d)     // 输出独热码
    );

    decoder_5_32 u2_decoder_5_32(
        .in  (rd),      // 输入寄存器rd
        .out (rd_d)     // 输出独热码
    );

    decoder_5_32 u3_decoder_5_32(
        .in  (sa),      // 输入移位量sa
        .out (sa_d)     // 输出独热码
    );

    // """算术运算指令"""

    // 加（可产生溢出例外）
    assign inst_add     = op_d[6'b00_0000] & func_d[6'b10_0000];
    // 加立即数（可产生溢出例外）
    assign inst_addi    = op_d[6'b00_1000];
    // 加（不产生溢出例外）
    assign inst_addu    = op_d[6'b00_0000] & func_d[6'b10_0001];
    // 加立即数（不产生溢出例外）
    assign inst_addiu   = op_d[6'b00_1001];
    // 减（可产生溢出例外）
    assign inst_sub     = op_d[6'b00_0000] & func_d[6'b10_0010];
    // 减（不产生溢出例外）
    assign inst_subu    = op_d[6'b00_0000] & func_d[6'b10_0011];
    // 有符号小于置1
    assign inst_slt     = op_d[6'b00_0000] & func_d[6'b10_1010];
    // 有符号小于立即数设置1
    assign inst_slti    = op_d[6'b00_1010];
    // 无符号小于设置1
    assign inst_sltu    = op_d[6'b00_0000] & func_d[6'b10_1011];
    // 无符号小于立即数设置1
    assign inst_sltiu   = op_d[6'b00_1011];
    // 有符号字除
    assign inst_div     = op_d[6'b00_0000] & func_d[6'b01_1010] & rd_d[5'b0_0000] & sa_d[5'b0_0000];
    // 无符号字除
    assign inst_divu    = op_d[6'b00_0000] & func_d[6'b01_1011] & rd_d[5'b0_0000] & sa_d[5'b0_0000];
    // 有符号字乘
    assign inst_mult    = op_d[6'b00_0000] & func_d[6'b01_1000] & rd_d[5'b0_0000] & sa_d[5'b0_0000];
    // 无符号字乘
    assign inst_multu   = op_d[6'b00_0000] & func_d[6'b01_1001] & rd_d[5'b0_0000] & sa_d[5'b0_0000];

    // """逻辑运算指令"""

    // 位与
    assign inst_and     = op_d[6'b00_0000] & func_d[6'b10_0100];
    // 立即数位与
    assign inst_andi    = op_d[6'b00_1100];
    // 寄存器高半部分置立即数
    assign inst_lui     = op_d[6'b00_1111];
    // 位或非
    assign inst_nor     = op_d[6'b00_0000] & func_d[6'b10_0111];
    // 位或
    assign inst_or      = op_d[6'b00_0000] & func_d[6'b10_0101];
    // 立即数位或
    assign inst_ori     = op_d[6'b00_1101];
    // 位异或
    assign inst_xor     = op_d[6'b00_0000] & func_d[6'b10_0110];
    // 立即数位异或
    assign inst_xori    = op_d[6'b00_1110];

    // """移位指令"""

    // 立即数逻辑左移
    assign inst_sll     = op_d[6'b00_0000] & func_d[6'b00_0000];
    // 变量逻辑左移
    assign inst_sllv     = op_d[6'b00_0000] & func_d[6'b00_0100];
    // 立即数算术右移
    assign inst_sra     = op_d[6'b00_0000] & func_d[6'b00_0011];
    // 变量算术右移
    assign inst_srav     = op_d[6'b00_0000] & func_d[6'b00_0111];
    // 立即数逻辑右移
    assign inst_srl     = op_d[6'b00_0000] & func_d[6'b00_0010];
    // 变量逻辑右移
    assign inst_srlv     = op_d[6'b00_0000] & func_d[6'b00_0110];

    // """分支跳转指令"""

    // 相等转移
    assign inst_beq     = op_d[6'b00_0100];
    // 不等转移
    assign inst_bne     = op_d[6'b00_0101];
    // 大于等于0转移
    assign inst_bnez     = op_d[6'b00_0001] & rt_d[5'b0_0001];
    // 大于0转移
    assign inst_bgtz     = op_d[6'b00_0111] & rt_d[5'b0_0000];
    // 小于等于0转移
    assign inst_blez     = op_d[6'b00_0110] & rt_d[5'b0_0000];
    // 小于0转移
    assign inst_bltz     = op_d[6'b00_0001] & rt_d[5'b0_0000];
    // 小于0调用子程序并保存返回地址
    assign inst_bgtzal     = op_d[6'b00_0001] & rt_d[5'b1_0000];
    // 大于等于0调用子程序并保存返回地址
    assign inst_bgezal     = op_d[6'b00_0001] & rt_d[5'b1_0001];
    // 大于等于0转移
    assign inst_bgez = op_d[6'b00_0001] & rt_d[5'b0_0001];

    // 无条件直接跳转
    assign inst_j     = op_d[6'b00_0010];
    // 无条件直接跳转至子程序并保存返回地址
    assign inst_jal     = op_d[6'b00_0011];
    // 无条件寄存器跳转
    assign inst_jr      = op_d[6'b00_0000] & func_d[6'b00_1000] & rt_d[5'b0_0000] & rd_d[5'b0_0000] & sa_d[5'b0_0000];
    // 无条件寄存器跳转至子程序并保存返回地址
    assign inst_jalr      = op_d[6'b00_0000]  & rt_d[5'b0_0000] & func_d[6'b00_1001];
    // 小于0调用子程序并保存返回地址
    assign inst_bltzal    = op_d[6'b00_0001] & rt_d[5'b1_0000];

    // """数据移动指令"""
    // HI寄存器至通用寄存器
    assign inst_mfhi    = op_d[6'b00_0000] & func_d[6'b01_0000] & rs_d[5'b0_0000] & rt_d[5'b0_0000] & sa_d[5'b0_0000];
    // LO寄存器至通用寄存器
    assign inst_mflo    = op_d[6'b00_0000] & func_d[6'b01_0010] & rs_d[5'b0_0000] & rt_d[5'b0_0000] & sa_d[5'b0_0000];
    // 通用寄存器至HI寄存器
    assign inst_mthi    = op_d[6'b00_0000] & func_d[6'b01_0001] & rt_d[5'b0_0000] & rd_d[5'b0_0000] & sa_d[5'b0_0000];
    // 通用寄存器至LO寄存器
    assign inst_mtlo    = op_d[6'b00_0000] & func_d[6'b01_0011] & rt_d[5'b0_0000] & rd_d[5'b0_0000] & sa_d[5'b0_0000];

    // """访存指令"""

    // 取字节有符号扩展
    assign inst_lb      = op_d[6'b10_0000];
    // 取字节无符号扩展
    assign inst_lbu     = op_d[6'b10_0100];
    // 取半字有符号扩展
    assign inst_lh      = op_d[6'b10_0001];
    // 取半字无符号扩展
    assign inst_lhu     = op_d[6'b10_0101];
    // 取字
    assign inst_lw      = op_d[6'b10_0011];
    // 存字节
    assign inst_sb      = op_d[6'b10_1000];
    // 存半字
    assign inst_sh      = op_d[6'b10_1001];
    // 存字
    assign inst_sw      = op_d[6'b10_1011];

    // rs到reg1的选择信号
    assign sel_alu_src1[0] =    inst_lw | inst_sw | inst_lb | inst_lbu  | inst_lh | inst_lhu | inst_sb | inst_sh |
                                inst_ori | inst_addiu | inst_or | inst_xor | inst_and  | inst_andi | inst_nor | inst_xori |
                                inst_sub | inst_subu | inst_add | inst_addi | inst_addu |
                                inst_jr | inst_bgezal | inst_bltzal |
                                inst_slti | inst_or | inst_srav | inst_sltu | inst_slt | inst_sltiu | inst_sllv | inst_srlv |
                                inst_div | inst_divu | inst_mult | inst_multu |
                                inst_mthi | inst_mtlo;
    // PC到reg1的选择信号
    assign sel_alu_src1[1] = inst_jal | inst_jalr | inst_bltzal | inst_bgezal;

    // 移位量零扩展到reg1的选择信号
    assign sel_alu_src1[2] = inst_sll | inst_sra | inst_srl;

    // rt到reg2的选择信号
    assign sel_alu_src2[0] =    inst_sub | inst_subu | inst_addu | inst_sll | inst_or | inst_xor | inst_sra | inst_srl |
                                inst_srlv | inst_sllv | inst_sra | inst_srav | inst_sltu | inst_slt  | inst_add | inst_and | inst_nor |
                                inst_div | inst_divu | inst_mult | inst_multu;

    // 立即数符号扩展到reg2的选择信号
    assign sel_alu_src2[1] =    inst_lui | inst_addiu | inst_slti | inst_sltiu | inst_addi |
                                inst_lw | inst_sw | inst_lb  | inst_lbu   | inst_lh  | inst_lhu | inst_sh | inst_sb;

    // 常数8到reg2的选择信号
    assign sel_alu_src2[2] = inst_jal | inst_jalr | inst_bgezal | inst_bltzal;

    // 立即数零扩展到reg2的选择信号
    assign sel_alu_src2[3] = inst_ori | inst_andi | inst_xori;

    // 组合不同类型的算术运算指令
    assign op_add = inst_add | inst_addi | inst_addiu |  inst_addu |  inst_add | inst_addi |
                    inst_jal | inst_jalr | inst_bltzal | inst_bgezal |
                    inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu |
                    inst_sw | inst_sb | inst_sh;

    assign op_sub = inst_subu | inst_sub;
    assign op_slt = inst_slt | inst_slti;
    assign op_sltu = inst_sltu | inst_sltiu;
    assign op_and = inst_and | inst_andi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xor | inst_xori;
    assign op_sll = inst_sll | inst_sllv;
    assign op_srl = inst_srl | inst_srlv;
    assign op_sra = inst_sra | inst_srav;
    assign op_lui = inst_lui;

    // ALU操作码组合
    // 12位ALU操作码，包含加、减、小于、与、或、异或、移位等操作
    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};

    // Load和Store使能信号
    assign data_ram_en = inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_sw | inst_sb | inst_sh;

    // Store指令写使能信号，Store指令需要写入内存
    assign data_ram_wen = inst_sw | inst_sb | inst_sh ? 4'b1111 : 4'b0000;

    // 寄存器文件写使能信号，根据不同指令类型决定是否写回寄存器
    assign rf_we =  inst_ori | inst_lui | inst_addiu | inst_subu | inst_addu | inst_add | inst_addi | inst_sub |
                    inst_jr | inst_jal | inst_jalr | inst_bgezal | inst_bltzal |
                    inst_sll | inst_sllv | inst_sra | inst_srl | inst_srlv | inst_srav |
                    inst_or | inst_xor | inst_xori | inst_and | inst_andi | inst_nor |
                    inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu |
                    inst_slt | inst_slti | inst_sltu | inst_sltiu |
                    inst_mfhi | inst_mflo;

    // 寄存器文件写地址选择逻辑
    // 根据目标寄存器选择信号，决定写入哪个寄存器
    // sel_rf_dst[0]：写入rd
    // sel_rf_dst[1]：写入rt
    // sel_rf_dst[2]：写入寄存器31
    assign sel_rf_dst[0] =  inst_sub | inst_subu | inst_addu |  inst_add |
                            inst_and | inst_nor | inst_or | inst_xor |
                            inst_slt | inst_sltu |
                            inst_jalr |
                            inst_sra | inst_srl | inst_srlv | inst_srav | inst_sll | inst_sllv |
                            inst_mfhi | inst_mflo;

    assign sel_rf_dst[1] =  inst_ori | inst_lui | inst_addiu | inst_addi | inst_slti | inst_sltiu |
                            inst_andi | inst_xori |
                            inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu;

    assign sel_rf_dst[2] = inst_jal | inst_jalr | inst_bltzal | inst_bgezal;

    // 根据选择信号选择寄存器文件的写地址
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd |
                      {5{sel_rf_dst[1]}} & rt |
                      {5{sel_rf_dst[2]}} & 5'd31;

    // 寄存器文件写数据来源选择信号
    // 0：来自ALU结果
    // 1：来自Load结果
    assign sel_rf_res = inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu ? 1'b1 : 1'b0;

    // 将ID阶段的数据总线打包传递到EX阶段
    assign id_to_ex_bus = {
        id_pc,          // 158:127 - 当前指令的PC
        inst,           // 126:95  - 当前指令
        alu_op,         // 94:83   - ALU操作码
        sel_alu_src1,   // 82:80   - ALU源操作数1的选择信号
        sel_alu_src2,   // 79:76   - ALU源操作数2的选择信号
        data_ram_en,    // 75      - 数据RAM使能信号
        data_ram_wen,   // 74:71   - 数据RAM写使能信号
        rf_we,          // 70      - 寄存器文件写使能信号
        rf_waddr,       // 69:65   - 寄存器文件写地址
        sel_rf_res,     // 64      - 寄存器文件结果选择信号
        ndata1,         // 63:32   - 处理后的数据1
        ndata2          // 31:0    - 处理后的数据2
    };

    // 分支跳转相关信号
    wire br_e;  // 分支条件满足标志
    wire [31:0] br_addr;  // 分支跳转地址
    wire rs_eq_rt;  // rs寄存器值等于rt寄存器值
    wire rs_ge_z;   // rs寄存器值大于等于0
    wire rs_gt_z;   // rs寄存器值大于0
    wire rs_le_z;   // rs寄存器值小于等于0
    wire rs_lt_z;   // rs寄存器值小于0
    wire [31:0] pc_plus_4;  // PC加4，用于计算下一条指令地址
    assign pc_plus_4 = id_pc + 32'h4;

    // 分支条件判断
    assign rs_eq_rt = (ndata1 == ndata2);  // rs等于rt
    assign rs_ge_z  = (!ndata1[31]);      // rs大于等于0（符号位为0）
    assign rs_gt_z  = ((!ndata1[31]) && ndata1 != 0);  // rs大于0（符号位为0且不为0）
    assign rs_le_z  = (ndata1 == 0 | ndata1[31]);     // rs小于等于0（等于0或符号位为1）
    assign rs_lt_z  = (ndata1[31]);                 // rs小于0（符号位为1）

    // 分支条件满足时，设置分支标志
    assign br_e = (inst_beq & rs_eq_rt) | (inst_j) | (inst_jalr) | |inst_jr | (inst_jal) |
                  (inst_bne & ~rs_eq_rt) |
                  (inst_bgez & rs_ge_z) | (inst_bgtz & rs_gt_z) |
                  (inst_blez & rs_le_z) | (inst_bltz & rs_lt_z) |
                  (inst_bgezal & rs_ge_z) | (inst_bltzal & rs_lt_z);

    // 根据指令类型计算分支跳转地址
    assign br_addr =
                        (inst_beq       ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_jr        ? ndata1 : 32'b0)                                           |
                        (inst_jal       ? {pc_plus_4[31:28], instr_index, 2'b0} : 32'b0)              |
                        (inst_j         ? ({pc_plus_4[31:28], instr_index, 2'b0}) : 32'b0)            |
                        (inst_jalr      ? ndata1 : 32'b0)                                             |
                        (inst_bne       ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_bgez      ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_bgtz      ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_blez      ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_bltz      ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_bgezal    ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0)   |
                        (inst_bltzal    ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0);

    // 将HI/LO寄存器相关信号打包传递到EX阶段
    assign id_hi_lo_bus = {
        inst_mfhi,
        inst_mflo,
        inst_mthi,
        inst_mtlo,
        inst_mult,
        inst_multu,
        inst_div,
        inst_divu,
        hi,
        lo
    };

    // 将Load指令类型信号打包传递到EX阶段
    assign id_load_bus = {
        inst_lb,
        inst_lbu,
        inst_lh,
        inst_lhu,
        inst_lw
    };

    // 将Save指令类型信号打包传递到EX阶段
    assign id_save_bus = {
        inst_sb,
        inst_sh,
        inst_sw
    };

    // 计算分支指令单元的停顿请求信号
    assign br_bus = {
        br_e,       // 分支条件满足标志
        br_addr     // 分支跳转地址
    };

    // 当EX阶段需要写回的寄存器与当前ID阶段的源寄存器相同时，发出停顿请求
    assign stallreq_for_bru = ex_id & (& ex_rf_we & (rs == ex_rf_waddr | rt == ex_rf_waddr)) ? `Stop : `NoStop;
    // ((ex_rf_we == 1'b1 && ex_rf_waddr == rs) ? `Stop : `NoStop | (ex_rf_we == 1'b1 && ex_rf_waddr == rt) ? `Stop : `NoStop)

endmodule
