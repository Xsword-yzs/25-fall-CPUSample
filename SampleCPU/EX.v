`include "lib/defines.vh"
module EX(
    input wire clk, // 时钟信号
    input wire rst, // 复位信号，高电平有效
    // input wire flush, // 流水线冲刷信号（当前未使用）
    input wire [`StallBus-1:0] stall, // 停顿信号，用于控制流水线暂停

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus, // 从ID阶段到EX阶段的数据总线
    // LW（加载字）和SW（存储字）：从ID阶段传递的加载和存储信号
    input wire [`LoadBus-1:0] id_load_bus, // Load信号总线，指示加载指令类型
    input wire [`SaveBus-1:0] id_save_bus, // Save信号总线，指示存储指令类型

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus, // 从EX阶段到MEM阶段的数据总线
    output wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus, // 从EX阶段到寄存器文件的数据总线
    input wire [71:0] id_hi_lo_bus, // 从ID阶段传递的HI/LO寄存器相关信号
    output wire [65:0] ex_hi_lo_bus, // EX阶段传递给下一阶段的HI/LO寄存器相关信号

    output wire stallreq_for_ex, // EX阶段发出的停顿请求信号
    output wire data_sram_en, // 数据SRAM使能信号
    output wire [3:0] data_sram_wen, // 数据SRAM写使能信号
    output wire [31:0] data_sram_addr, // 数据SRAM地址
    output wire [31:0] data_sram_wdata, // 数据SRAM写数据
    output wire ex_id, // EX阶段标识信号
    output wire [3:0] data_ram_sel, // 数据RAM选择信号
    output wire [`LoadBus-1:0] ex_load_bus // EX阶段Load信号总线，传递具体的Load指令类型
);
    // 寄存器，用于保存来自ID阶段的数据
    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r; // 暂存ID到EX的数据总线
    reg [`LoadBus-1:0] id_load_bus_r; // 暂存Load信号
    reg [`SaveBus-1:0] id_save_bus_r; // 暂存Save信号
    reg [71:0] id_hi_lo_bus_r; // 暂存HI/LO相关信号
    
    // 时钟上升沿时，更新寄存器的值
    always @ (posedge clk) begin
        // 复位时，清空寄存器，恢复初始状态
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
            id_save_bus_r <= `SaveBus'b0;
            id_load_bus_r <= `LoadBus'b0;
            id_hi_lo_bus_r <= 72'b0;
        end
        // else if (flush) begin
        //如果收到冲刷信号，清空寄存器（当前未启用）
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            // 当stall信号为停顿且后续不继续停顿时，清空寄存器
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
            id_save_bus_r <= `SaveBus'b0;
            id_load_bus_r <= `LoadBus'b0;
            id_hi_lo_bus_r <= 72'b0;
        end
        else if (stall[2]==`NoStop) begin
            // 当stall信号不为停顿时，更新寄存器，传递ID阶段的数据到EX阶段
            id_to_ex_bus_r <= id_to_ex_bus;
            id_save_bus_r <= id_save_bus;
            id_load_bus_r <= id_load_bus;
            id_hi_lo_bus_r <= id_hi_lo_bus;
        end
    end
    // EX阶段的各个信号
    wire [31:0] ex_pc, inst; // 当前指令的程序计数器(PC)和指令内容
    wire [11:0] alu_op; // ALU操作码，用于指示ALU执行的运算类型
    wire [2:0] sel_alu_src1; // ALU源操作数1的选择信号
    wire [3:0] sel_alu_src2; // ALU源操作数2的选择信号
    wire data_ram_en; // 数据RAM使能信号，指示是否进行访存操作
    wire [3:0] data_ram_wen; // 数据RAM写使能信号，控制写入哪些字节
    wire rf_we; // 寄存器文件写使能信号，指示是否写回寄存器
    wire [4:0] rf_waddr; // 寄存器文件写地址，指定写回的寄存器编号
    wire sel_rf_res; // 寄存器文件结果选择信号，选择写回数据的来源
    wire [31:0] rf_rdata1, rf_rdata2; // 寄存器文件读出的数据1和数据2
    reg is_in_delayslot; // 标志是否处于延迟槽（分支指令后的指令）
    wire [3:0] byte_sel; // 字节选择信号，用于数据存储
    // 从寄存器`id_to_ex_bus_r`中解码出各个信号
    assign {
        ex_pc,          // 158:127 - 当前指令的PC
        inst,           // 126:95 - 当前指令
        alu_op,         // 94:83 - ALU操作码
        sel_alu_src1,   // 82:80 - ALU源操作数1的选择信号
        sel_alu_src2,   // 79:76 - ALU源操作数2的选择信号
        data_ram_en,    // 75 - 数据RAM使能信号
        data_ram_wen,   // 74:71 - 数据RAM写使能信号
        rf_we,          // 70 - 寄存器文件写使能信号
        rf_waddr,       // 69:65 - 寄存器文件写地址
        sel_rf_res,     // 64 - 寄存器文件结果选择信号
        rf_rdata1,      // 63:32 - 寄存器文件读数据1
        rf_rdata2       // 31:0 - 寄存器文件读数据2
    } = id_to_ex_bus_r;
    // 对立即数进行符号扩展和零扩展
    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]}; // 符号扩展，将立即数的高16位填充为符号位
    assign imm_zero_extend = {16'b0, inst[15:0]}; // 零扩展，将立即数的高16位填充为0
    assign sa_zero_extend = {27'b0,inst[10:6]}; // 位移扩展，将位移量扩展到32位
    // ALU的两个源操作数
    wire [31:0] alu_src1, alu_src2; // ALU源操作数1和源操作数2
    wire [31:0] alu_result, ex_result; // ALU运算结果和EX阶段的最终结果

    // 识别load和save指令
    wire inst_lb, inst_lbu, inst_lh, inst_lhu, inst_lw; // Load指令类型：加载字节、加载字节无符号、加载半字、加载半字无符号、加载字
    wire inst_sb, inst_sh, inst_sw; // Store指令类型：存储字节、存储半字、存储字

    // 识别HI/LO寄存器相关指令
    wire inst_mfhi, inst_mflo, inst_mthi, inst_mtlo; // HI/LO寄存器操作指令
    wire inst_mult, inst_multu; // 乘法指令：有符号乘法和无符号乘法
    wire inst_div, inst_divu; // 除法指令：有符号除法和无符号除法

    wire [31:0] hi; // HI寄存器数据
    wire [31:0] lo; // LO寄存器数据
    wire hi_we; // HI寄存器写使能信号
    wire lo_we; // LO寄存器写使能信号
    wire [31:0] hi_wdata; // HI寄存器写入数据
    wire [31:0] lo_wdata; // LO寄存器写入数据

    // 从HI/LO总线中解码出各个信号
    assign {
        inst_mfhi,   // 指令：将HI寄存器的值移动到通用寄存器
        inst_mflo,   // 指令：将LO寄存器的值移动到通用寄存器
        inst_mthi,   // 指令：将通用寄存器的值移动到HI寄存器
        inst_mtlo,   // 指令：将通用寄存器的值移动到LO寄存器
        inst_mult,   // 指令：有符号乘法
        inst_multu,  // 指令：无符号乘法
        inst_div,    // 指令：有符号除法
        inst_divu,   // 指令：无符号除法
        hi,          // HI寄存器当前值
        lo           // LO寄存器当前值
    } = id_hi_lo_bus_r;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc : // 如果sel_alu_src1[1]为1，选择PC作为ALU源操作数1
                      sel_alu_src1[2] ? sa_zero_extend : // 如果sel_alu_src1[2]为1，选择位移扩展后的值作为ALU源操作数1
                      rf_rdata1; // 否则，选择寄存器读出的数据1作为ALU源操作数1


    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend : // 如果sel_alu_src2[1]为1，选择符号扩展的立即数作为ALU源操作数2
                      sel_alu_src2[2] ? 32'd8 : // 如果sel_alu_src2[2]为1，选择常数8作为ALU源操作数2
                      sel_alu_src2[3] ? imm_zero_extend : // 如果sel_alu_src2[3]为1，选择零扩展的立即数作为ALU源操作数2
                      rf_rdata2; // 否则，选择寄存器读出的数据2作为ALU源操作数2
    // 实例化ALU模块，执行算术或逻辑运算
    alu u_alu(
    	.alu_control (alu_op), // ALU操作码，决定ALU执行何种运算
        .alu_src1    (alu_src1), // ALU源操作数1
        .alu_src2    (alu_src2), // ALU源操作数2
        .alu_result  (alu_result) // ALU运算结果
    );

    assign ex_result = inst_mfhi ? hi : // 如果指令是MFHI，则EX结果为HI寄存器的值
                        inst_mflo ? lo : // 如果指令是MFLO，则EX结果为LO寄存器的值
                        alu_result; // 否则，EX结果为ALU的运算结果

    // 实例化2转4解码器，用于字节选择
    decoder_2_4 u_decoder_2_4(
        .in  (ex_result[1:0]), // 输入为ALU结果的最低两位，用于字节选择
        .out (byte_sel) // 输出为4位字节选择信号
    );

    // EX到MEM的数据总线，传递必要的信息到内存阶段
    assign ex_to_mem_bus = {
        ex_pc,         // 75:44 - 当前指令的PC
        data_ram_en,   // 43 - 数据RAM使能信号
        data_ram_wen,  // 42:39 - 数据RAM写使能信号
        sel_rf_res,    // 38 - 寄存器文件结果选择信号
        rf_we,         // 37 - 寄存器文件写使能信号
        rf_waddr,      // 36:32 - 寄存器文件写地址
        ex_result      // 31:0 - EX阶段运算结果
    };

    assign ex_id = sel_rf_res; // EX阶段标识信号，指示是否需要将结果写回寄存器

    // 转发信号，传递结果到寄存器文件
    assign ex_to_rf_bus = {
        rf_we,      // 37 - 寄存器文件写使能信号
        rf_waddr,   // 36:32 - 寄存器文件写地址
        ex_result   // 31:0 - EX阶段运算结果
    };

    // 从Load和Save总线中解码出具体的指令类型
    assign {
        inst_lb,
        inst_lbu,
        inst_lh,
        inst_lhu,
        inst_lw
    } = id_load_bus_r; // 解码Load指令类型信号

    assign {
        inst_sb,
        inst_sh,
        inst_sw
    } = id_save_bus_r; // 解码Store指令类型信号

    // 将Load信号传递到EX阶段的Load总线
    assign ex_load_bus = {
        inst_lb,   // 加载字节
        inst_lbu,  // 加载字节无符号
        inst_lh,   // 加载半字
        inst_lhu,  // 加载半字无符号
        inst_lw    // 加载字
    };

    // 数据RAM选择信号，根据指令类型和地址选择写入的字节
    assign data_ram_sel =   inst_sb | inst_lb | inst_lbu ? byte_sel :                                     // 存储字节或加载字节指令，选择特定字节
                            inst_sh | inst_lh | inst_lhu ? {{2{byte_sel[2]}}, {2{byte_sel[0]}}} :        // 存储半字或加载半字指令，选择特定的两个字节
                            inst_sw | inst_lw ? 4'b1111 : 4'b0000;                                       // 存储字或加载字指令，选择全部字节

    // 数据SRAM使能信号
    assign data_sram_en = data_ram_en;

    // 根据写地址的最低两位addr[1:0]判断写使能信号
    assign data_sram_wen = {4{data_ram_wen}} & data_ram_sel;

    // 数据SRAM地址
    assign data_sram_addr = ex_result;

    // 数据SRAM写数据，根据指令类型选择写入的数据
    assign data_sram_wdata  =   inst_sb ? {4{rf_rdata2[7:0]}} :         // 存储字节指令，重复最低8位数据到所有字节
                                inst_sh ? {2{rf_rdata2[15:0]}} :        // 存储半字指令，重复最低16位数据到两个字节
                                rf_rdata2;                             // 存储字指令，直接写入32位数据

    // EX到HI/LO的数据总线，传递HI/LO寄存器的写使能和写数据
    assign ex_hi_lo_bus = {
        hi_we,     // HI寄存器写使能信号
        lo_we,     // LO寄存器写使能信号
        hi_wdata,  // HI寄存器写入数据
        lo_wdata   // LO寄存器写入数据
    };

    // MUL部分：有符号或无符号乘法
    wire [63:0] mul_result; // 乘法结果，64位
    wire mul_signed; // 有符号乘法标记

    assign mul_signed = inst_mult; // 如果是有符号乘法指令，则mul_signed为1

    // 实例化乘法模块，执行乘法运算
    mul u_mul(
    	.clk        (clk), // 时钟信号
        .resetn     (~rst), // 复位信号，低电平有效
        .mul_signed (mul_signed), // 有符号乘法标记
        .ina        (rf_rdata1), // 乘法源操作数1
        .inb        (rf_rdata2), // 乘法源操作数2
        .result     (mul_result) // 乘法结果 64bit
    );

    // DIV部分：有符号或无符号除法
    wire [63:0] div_result; // 除法结果，64位
    wire div_ready_i; // 除法模块准备好信号
    reg stallreq_for_div; // DIV阶段发出的停顿请求信号
    assign stallreq_for_ex = stallreq_for_div; // 将DIV阶段的停顿请求传递给EX阶段

    reg [31:0] div_opdata1_o; // 除法操作数1输出寄存器
    reg [31:0] div_opdata2_o; // 除法操作数2输出寄存器
    reg div_start_o; // 除法启动信号
    reg signed_div_o; // 有符号除法标记

    // 实例化除法模块，执行除法运算
    div u_div(
    	.rst          (rst), // 复位信号，高电平有效
        .clk          (clk), // 时钟信号
        .signed_div_i (signed_div_o ), // 有符号除法标记
        .opdata1_i    (div_opdata1_o), // 除法操作数1
        .opdata2_i    (div_opdata2_o), // 除法操作数2
        .start_i      (div_start_o), // 除法启动信号
        .annul_i      (1'b0), // 除法取消信号，固定为0
        .result_o     (div_result), // 除法结果，64bit
        .ready_o      (div_ready_i) // 除法模块准备好信号
    );

    // 处理除法运算的停顿请求和控制信号
    always @ (*) begin
        if (rst) begin
            // 复位时，初始化除法相关信号
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            // 默认情况下，不请求停顿，停止除法操作
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin
                    // 有符号除法指令
                    if (div_ready_i == `DivResultNotReady) begin
                        // 除法结果未准备好，启动除法运算并请求停顿
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        // 除法结果已准备好，停止除法运算并不请求停顿
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        // 其他情况，不启动除法运算且不请求停顿
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01:begin
                    // 无符号除法指令
                    if (div_ready_i == `DivResultNotReady) begin
                        // 除法结果未准备好，启动除法运算并请求停顿
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        // 除法结果已准备好，停止除法运算并不请求停顿
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        // 其他情况，不启动除法运算且不请求停顿
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end

    // hi_we和lo_we的赋值，根据指令类型决定是否写HI/LO寄存器
    assign hi_we = inst_mthi | inst_mult | inst_multu | inst_div | inst_divu;  // HI寄存器写使能
    assign lo_we = inst_mtlo | inst_mult | inst_multu | inst_div | inst_divu;  // LO寄存器写使能

    // HI寄存器写入数据的选择逻辑
    assign hi_wdata = inst_mthi ? rf_rdata1 :                             // MTHI指令，将寄存器数据写入HI
                      inst_mult | inst_multu ? mul_result[63:32] :        // 乘法指令，将乘法结果高32位写入HI
                      inst_div | inst_divu ? div_result[63:32] :          // 除法指令，将除法结果高32位写入HI
                      32'b0;                                            // 其他情况，写入0

    // LO寄存器写入数据的选择逻辑
    assign lo_wdata = inst_mtlo ? rf_rdata1 :                             // MTLO指令，将寄存器数据写入LO
                      inst_mult | inst_multu ? mul_result[31:0] :         // 乘法指令，将乘法结果低32位写入LO
                      inst_div | inst_divu ? div_result[31:0] :           // 除法指令，将除法结果低32位写入LO
                      32'b0;                    
    
    
endmodule