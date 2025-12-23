`include "lib/defines.vh"  

// 指令解码，同时读取寄存器
// IF/ID阶段可能会取出经符号扩展为32位的立即数和两个从寄存器中读取的数，放入ID/EX流水线寄存器

// 需要在该级进行指令译码
// 从寄存器中读取需要的数据
// 完成数据相关处理
// 生成发给EX段的控制信号

module ID(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    input wire [`StallBus-1:0] stall,  // 停顿信号，控制流水线停顿
    output wire stallreq,  // 请求停顿信号

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 来自IF阶段的数据（包括PC值）
    input wire [31:0] inst_sram_rdata,  // 指令存储器读取的数据

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 来自WB阶段的写回信号，含有写回的数据
    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,  // 传递给EX阶段的数据
    output wire [`BR_WD-1:0] br_bus  // 分支信号（是否分支和分支地址）
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;  // 存储来自IF阶段的数据
    wire [31:0] inst;  // 当前指令
    wire [31:0] id_pc;  // 当前PC值
    wire ce;  // 控制信号，指示IF阶段是否有效

    wire wb_rf_we;  // WB阶段是否写回寄存器
    wire [4:0] wb_rf_waddr;  // WB阶段写回的寄存器地址
    wire [31:0] wb_rf_wdata;  // WB阶段写回的寄存器数据

    // 同步if_to_id_bus数据，存储并处理流水线停顿信号
    always @ (posedge clk) begin
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;  // 复位时清零
        end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;  // 如果存在停顿，则清零
        end
        else if (stall[1]==`NoStop) begin
            if_to_id_bus_r <= if_to_id_bus;  // 如果没有停顿，则传递if_to_id_bus数据
        end
    end

    // 提取IF阶段传来的PC值和控制信号
    assign inst = inst_sram_rdata;
    assign { ce, id_pc } = if_to_id_bus_r;

    // 从WB阶段获取写回信号
    assign { wb_rf_we, wb_rf_waddr, wb_rf_wdata } = wb_to_rf_bus;

    // 解码指令字段
    wire [5:0] opcode;  // 操作码
    wire [4:0] rs, rt, rd, sa;  // 寄存器操作数
    wire [5:0] func;  // 功能码
    wire [15:0] imm;  // 立即数
    wire [25:0] instr_index;  // 指令索引（对于跳转指令）
    wire [19:0] code;  // 代码
    wire [4:0] base;  // 基地址
    wire [15:0] offset;  // 偏移量
    wire [2:0] sel;  // 选择信号

    // 提取指令的各个字段
    assign opcode = inst[31:26];
    assign rs = inst[25:21];
    assign rt = inst[20:16];
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];
    assign sel = inst[2:0];

    // 解码器模块实例，解码操作码和功能码
    wire [63:0] op_d, func_d;
    wire [31:0] rs_d, rt_d, rd_d, sa_d;

    decoder_6_64 u0_decoder_6_64(
        .in(opcode),
        .out(op_d)
    );

    decoder_6_64 u1_decoder_6_64(
        .in(func),
        .out(func_d)
    );

    decoder_5_32 u0_decoder_5_32(
        .in(rs),
        .out(rs_d)
    );

    decoder_5_32 u1_decoder_5_32(
        .in(rt),
        .out(rt_d)
    );

    // 定义特定指令类型
    wire inst_ori, inst_lui, inst_addiu, inst_beq;
    assign inst_ori = op_d[6'b00_1101];
    assign inst_lui = op_d[6'b00_1111];
    assign inst_addiu = op_d[6'b00_1001];
    assign inst_beq = op_d[6'b00_0100];

    // ALU输入选择信号
    assign sel_alu_src1[0] = inst_ori | inst_addiu;
    assign sel_alu_src1[1] = 1'b0;
    assign sel_alu_src1[2] = 1'b0;
    assign sel_alu_src2[0] = 1'b0;
    assign sel_alu_src2[1] = inst_lui | inst_addiu;
    assign sel_alu_src2[2] = 1'b0;
    assign sel_alu_src2[3] = inst_ori;

    // ALU操作类型定义
    assign op_add = inst_addiu;
    assign op_sub = 1'b0;
    assign op_slt = 1'b0;
    assign op_sltu = 1'b0;
    assign op_and = 1'b0;
    assign op_nor = 1'b0;
    assign op_or = inst_ori;
    assign op_xor = 1'b0;
    assign op_sll = 1'b0;
    assign op_srl = 1'b0;
    assign op_sra = 1'b0;
    assign op_lui = inst_lui;

    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};

    // 控制数据存储器使能信号（本模块不涉及实际的存储器操作）
    assign data_ram_en = 1'b0;
    assign data_ram_wen = 1'b0;

    // 寄存器写使能信号
    assign rf_we = inst_ori | inst_lui | inst_addiu;

    // 寄存器写地址选择
    assign sel_rf_dst[0] = 1'b0;  // 不写寄存器rd
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu;  // 写寄存器rt
    assign sel_rf_dst[2] = 1'b0;  // 不写寄存器31

    // 寄存器写地址计算
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    // 寄存器写回选择信号
    assign sel_rf_res = 1'b0;

    // 传递给EX阶段的数据
    assign id_to_ex_bus = {
        id_pc,          // PC值
        inst,           // 当前指令
        alu_op,         // ALU操作码
        sel_alu_src1,   // ALU输入选择1
        sel_alu_src2,   // ALU输入选择2
        data_ram_en,    // 数据存储器使能
        data_ram_wen,   // 数据存储器写使能
        rf_we,          // 寄存器写使能
        rf_waddr,       // 寄存器写地址
        sel_rf_res,     // 写回数据选择
        rdata1,         // 寄存器数据1
        rdata2          // 寄存器数据2
    };

    // 分支判断：如果是BEQ指令且rs与rt相等，则分支
    wire br_e;
    wire [31:0] br_addr;
    wire rs_eq_rt;
    wire rs_ge_z;
    wire rs_gt_z;
    wire rs_le_z;
    wire rs_lt_z;

    wire [31:0] pc_plus_4;
    assign pc_plus_4 = id_pc + 32'h4;
    assign rs_eq_rt = (rdata1 == rdata2);
    assign br_e = inst_beq & rs_eq_rt;  // BEQ条件成立时，进行分支
    assign br_addr = inst_beq ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0;

    assign br_bus = {
        br_e,          // 分支使能信号
        br_addr        // 分支地址
    };
    
endmodule