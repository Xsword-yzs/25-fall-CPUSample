`include "lib/defines.vh"

// 执行运算或计算地址（反正就是和ALU相关）
// 从ID/EX流水线寄存器中读取由寄存器1传过来的值和寄存器2传过来的值
// （或寄存器1传过来的值和符号扩展过后的立即数的值），
// 并用ALU将它们相加，结果值存入EX/MEM流水线寄存器。

// alu模块已经提供，基本通过给alu提供控制信号就可以完成逻辑和算术运算
// 对于需要访存的指令在此段发出访存请求



module EX(
    input wire clk,
    input wire rst,
    // input wire flush,  // 取消注释可用于处理指令刷新信号
    input wire [`StallBus-1:0] stall,  // 流水线停顿信号

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,  // 来自ID阶段的数据总线

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,  // 传递给MEM阶段的数据总线

    output wire data_sram_en,  // 数据存储器使能信号
    output wire [3:0] data_sram_wen,  // 数据存储器写使能信号
    output wire [31:0] data_sram_addr,  // 数据存储器地址
    output wire [31:0] data_sram_wdata  // 数据存储器写数据
);

    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;  // 存储从ID阶段接收的数据

    // 流水线寄存器同步
    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;  // 复位时清空寄存器
        end
        // else if (flush) begin
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;  // 清空指令（用于指令刷新）
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;  // 流水线停顿时清空寄存器
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus;  // 如果没有停顿，传递数据
        end
    end

    // 从id_to_ex_bus_r中提取出各个信号
    wire [31:0] ex_pc, inst;
    wire [11:0] alu_op;
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [31:0] rf_rdata1, rf_rdata2;

    assign {
        ex_pc,          // PC值
        inst,           // 当前指令
        alu_op,         // ALU操作码
        sel_alu_src1,   // ALU源1选择
        sel_alu_src2,   // ALU源2选择
        data_ram_en,    // 数据存储器使能
        data_ram_wen,   // 数据存储器写使能
        rf_we,          // 寄存器写使能
        rf_waddr,       // 寄存器写地址
        sel_rf_res,     // 寄存器写回选择
        rf_rdata1,      // 寄存器1的值
        rf_rdata2       // 寄存器2的值
    } = id_to_ex_bus_r;

    // 立即数扩展（符号扩展、零扩展）
    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}}, inst[15:0]};  // 符号扩展
    assign imm_zero_extend = {16'b0, inst[15:0]};  // 零扩展
    assign sa_zero_extend = {27'b0, inst[10:6]};  // 移位操作符的立即数扩展

    // ALU源操作数选择
    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : rf_rdata1;  // ALU源1
    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend : rf_rdata2;  // ALU源2

    // ALU实例
    alu u_alu(
        .alu_control(alu_op),
        .alu_src1(alu_src1),
        .alu_src2(alu_src2),
        .alu_result(alu_result)
    );

    assign ex_result = alu_result;  // ALU执行结果

    // 传递给MEM阶段的数据总线
    assign ex_to_mem_bus = {
        ex_pc,          // PC值
        data_ram_en,    // 数据存储器使能
        data_ram_wen,   // 数据存储器写使能
        sel_rf_res,     // 寄存器写回选择
        rf_we,          // 寄存器写使能
        rf_waddr,       // 寄存器写地址
        ex_result       // 执行结果
    };

    // 乘法部分
    wire [63:0] mul_result;
    wire mul_signed;  // 有符号乘法标记

    mul u_mul(
        .clk(clk),
        .resetn(~rst),
        .mul_signed(mul_signed),
        .ina(rf_rdata1),  // 乘法操作数1
        .inb(rf_rdata2),  // 乘法操作数2
        .result(mul_result)  // 乘法结果
    );

    // 除法部分
    wire [63:0] div_result;
    wire inst_div, inst_divu;
    wire div_ready_i;
    reg stallreq_for_div;  // 除法操作的停顿请求
    assign stallreq_for_ex = stallreq_for_div;  // 向上游请求停顿

    reg [31:0] div_opdata1_o;
    reg [31:0] div_opdata2_o;
    reg div_start_o;
    reg signed_div_o;

    div u_div(
        .rst(rst),
        .clk(clk),
        .signed_div_i(signed_div_o),
        .opdata1_i(div_opdata1_o),
        .opdata2_i(div_opdata2_o),
        .start_i(div_start_o),
        .annul_i(1'b0),
        .result_o(div_result),
        .ready_o(div_ready_i)
    );

    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div, inst_divu})
                2'b10: begin  // 除法指令
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01: begin  // 无符号除法指令
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default: begin
                    // 其他情况
                end
            endcase
        end
    end

    // mul_result 和 div_result 可以直接使用
endmodule