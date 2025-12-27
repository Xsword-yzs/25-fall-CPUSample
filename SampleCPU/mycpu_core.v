`include "lib/defines.vh"   // 引入定义文件，其中包含了各种常量和总线宽度等定义

// mycpu_core模块定义
// 包括了CPU的五个基本阶段（IF、ID、EX、MEM、WB）和控制逻辑模块
module mycpu_core(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    input wire [5:0] int,  // 外部中断信号，宽度为6位

    // 指令存储器接口
    output wire inst_sram_en,    // 指令存储器使能信号
    output wire [3:0] inst_sram_wen,  // 指令存储器写使能信号（4位，分别表示四个字节）
    output wire [31:0] inst_sram_addr, // 指令存储器地址（32位）
    output wire [31:0] inst_sram_wdata, // 指令存储器写数据（32位）
    input wire [31:0] inst_sram_rdata,  // 指令存储器读数据（32位）

    // 数据存储器接口
    output wire data_sram_en,    // 数据存储器使能信号
    output wire [3:0] data_sram_wen,  // 数据存储器写使能信号（4位，分别表示四个字节）
    output wire [31:0] data_sram_addr, // 数据存储器地址（32位）
    output wire [31:0] data_sram_wdata, // 数据存储器写数据（32位）
    input wire [31:0] data_sram_rdata,  // 数据存储器读数据（32位）

    // 调试信息接口
    output wire [31:0] debug_wb_pc,      // 写回阶段的程序计数器值
    output wire [3:0] debug_wb_rf_wen,   // 写回阶段的寄存器写使能信号
    output wire [4:0] debug_wb_rf_wnum,  // 写回阶段的寄存器写地址
    output wire [31:0] debug_wb_rf_wdata // 写回阶段的寄存器写数据
);

    // 连接各个流水线模块的总线信号
    wire [`IF_TO_ID_WD-1:0] if_to_id_bus;   // IF阶段到ID阶段的总线
    wire [`ID_TO_EX_WD-1:0] id_to_ex_bus;   // ID阶段到EX阶段的总线
    wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus; // EX阶段到MEM阶段的总线
    wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus; // MEM阶段到WB阶段的总线
    wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus;   // EX阶段到RF（寄存器堆）的总线
    wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus; // MEM阶段到RF（寄存器堆）的总线
    wire [`BR_WD-1:0] br_bus;               // 分支相关的信号总线
    wire [`DATA_SRAM_WD-1:0] ex_dt_sram_bus; // 数据存储器相关的总线
    wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus;   // WB阶段到RF（寄存器堆）的总线
    wire [`LoadBus-1:0] id_load_bus;        // ID阶段的加载信号总线
    wire [`LoadBus-1:0] ex_load_bus;        // EX阶段的加载信号总线
    wire [3:0] data_ram_sel;                // 数据存储器的选择信号（4位）
    wire [`SaveBus-1:0] id_save_bus;        // ID阶段的保存信号总线
    wire [`StallBus-1:0] stall;             // 流水线停顿信号

    // IF模块（取指阶段）
    IF u_IF(
    	.clk             (clk             ),    // 时钟信号
        .rst             (rst             ),    // 复位信号
        .stall           (stall           ),    // 停顿信号
        .br_bus          (br_bus          ),    // 分支相关信号
        .if_to_id_bus    (if_to_id_bus    ),    // IF阶段到ID阶段的总线
        .inst_sram_en    (inst_sram_en    ),    // 指令存储器使能信号
        .inst_sram_wen   (inst_sram_wen   ),    // 指令存储器写使能信号
        .inst_sram_addr  (inst_sram_addr  ),    // 指令存储器地址
        .inst_sram_wdata (inst_sram_wdata )     // 指令存储器写数据
    );

    // ID模块（译码阶段）
    ID u_ID(
    	.clk             (clk             ),    // 时钟信号
        .rst             (rst             ),    // 复位信号
        .stall           (stall           ),    // 停顿信号
        .stallreq        (stallreq        ),    // 停顿请求信号
        .if_to_id_bus    (if_to_id_bus    ),    // IF阶段到ID阶段的总线
        .inst_sram_rdata (inst_sram_rdata ),    // 指令存储器读数据
        .wb_to_rf_bus    (wb_to_rf_bus    ),    // WB阶段到RF的总线
        .ex_to_rf_bus    (ex_to_rf_bus    ),    // EX阶段到RF的总线
        .mem_to_rf_bus   (mem_to_rf_bus   ),    // MEM阶段到RF的总线
        .id_to_ex_bus    (id_to_ex_bus    ),    // ID阶段到EX阶段的总线
        .id_load_bus     (id_load_bus     ),    // ID阶段的加载信号
        .id_save_bus     (id_save_bus     ),    // ID阶段的保存信号
        .br_bus          (br_bus          )     // 分支相关信号
    );

    // EX模块（执行阶段）
    EX u_EX(
    	.clk             (clk             ),    // 时钟信号
        .rst             (rst             ),    // 复位信号
        .stall           (stall           ),    // 停顿信号
        .id_to_ex_bus    (id_to_ex_bus    ),    // ID阶段到EX阶段的总线
        .ex_to_rf_bus    (ex_to_rf_bus    ),    // EX阶段到RF的总线
        .ex_to_mem_bus   (ex_to_mem_bus   ),    // EX阶段到MEM的总线
        .id_load_bus     (id_load_bus     ),    // ID阶段的加载信号
        .id_save_bus     (id_save_bus     ),    // ID阶段的保存信号
        .ex_load_bus     (ex_load_bus     ),    // EX阶段的加载信号
        .data_ram_sel    (data_ram_sel    ),    // 数据存储器的选择信号
        .data_sram_en    (data_sram_en    ),    // 数据存储器使能信号
        .data_sram_wen   (data_sram_wen   ),    // 数据存储器写使能信号
        .data_sram_addr  (data_sram_addr  ),    // 数据存储器地址
        .data_sram_wdata (data_sram_wdata )     // 数据存储器写数据
    );

    // MEM模块（访存阶段）
    MEM u_MEM(
    	.clk             (clk             ),    // 时钟信号
        .rst             (rst             ),    // 复位信号
        .stall           (stall           ),    // 停顿信号
        .ex_to_mem_bus   (ex_to_mem_bus   ),    // EX阶段到MEM阶段的总线
        .ex_load_bus     (ex_load_bus     ),    // EX阶段的加载信号
        .data_sram_rdata (data_sram_rdata ),    // 数据存储器读数据
        .data_ram_sel    (data_ram_sel    ),    // 数据存储器的选择信号
        .mem_to_wb_bus   (mem_to_wb_bus   ),    // MEM阶段到WB阶段的总线
        .mem_to_rf_bus   (mem_to_rf_bus   )     // MEM阶段到RF的总线
    );

    // WB模块（写回阶段）
    WB u_WB(
    	.clk               (clk               ),    // 时钟信号
        .rst               (rst               ),    // 复位信号
        .stall             (stall             ),    // 停顿信号
        .mem_to_wb_bus     (mem_to_wb_bus     ),    // MEM阶段到WB阶段的总线
        .wb_to_rf_bus      (wb_to_rf_bus      ),    // WB阶段到RF的总线
        .debug_wb_pc       (debug_wb_pc       ),    // 写回阶段的程序计数器值
        .debug_wb_rf_wen   (debug_wb_rf_wen   ),    // 写回阶段的寄存器写使能信号
        .debug_wb_rf_wnum  (debug_wb_rf_wnum  ),    // 写回阶段的寄存器写地址
        .debug_wb_rf_wdata (debug_wb_rf_wdata )     // 写回阶段的寄存器写数据
    );

endmodule