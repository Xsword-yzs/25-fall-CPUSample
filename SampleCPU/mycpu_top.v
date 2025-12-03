`include "lib/defines.vh"  // 引入定义文件，包含各种宏定义和参数

// CPU顶层模块，集成了核心处理器和内存管理单元（MMU）
module mycpu_top(
    input wire clk,                   // 时钟信号
    input wire resetn,                // 复位信号，低电平有效
    input wire [5:0] ext_int,         // 外部中断信号

    // 指令存储器接口
    output wire inst_sram_en,         // 指令存储器使能信号，控制是否进行读操作
    output wire [3:0] inst_sram_wen,  // 指令存储器写使能信号，通常固定为4'b0000，表示不进行写操作
    output wire [31:0] inst_sram_addr, // 指令存储器地址，经过MMU转换后的物理地址
    output wire [31:0] inst_sram_wdata, // 指令存储器写数据，通常固定为32'b0，表示不进行写操作
    input wire [31:0] inst_sram_rdata,  // 指令存储器读数据，从存储器中读取到的指令

    // 数据存储器接口
    output wire data_sram_en,         // 数据存储器使能信号，控制数据存储器的读写操作
    output wire [3:0] data_sram_wen,  // 数据存储器写使能信号，决定写入哪些字节
    output wire [31:0] data_sram_addr, // 数据存储器地址，经过MMU转换后的物理地址
    output wire [31:0] data_sram_wdata, // 数据存储器写数据，包含要写入的数据
    input wire [31:0] data_sram_rdata,  // 数据存储器读数据，从存储器中读取到的数据

    // 调试信号
    output wire [31:0] debug_wb_pc,        // 写回阶段的PC值，用于调试和监控
    output wire [3:0] debug_wb_rf_wen,     // 写回阶段的寄存器写使能信号，4位宽
    output wire [4:0] debug_wb_rf_wnum,    // 写回阶段的寄存器写地址，5位宽
    output wire [31:0] debug_wb_rf_wdata   // 写回阶段的寄存器写数据，32位宽
);

    // 内部信号定义
    wire [31:0] inst_sram_addr_v, data_sram_addr_v; // 虚拟地址信号

    // 实例化核心处理器模块
    mycpu_core u_mycpu_core(
        .clk               (clk               ), // 时钟信号
        .rst               (~resetn           ), // 复位信号，低电平有效，取反后高电平有效
        .int               (ext_int           ), // 外部中断信号
        .inst_sram_en      (inst_sram_en      ), // 指令存储器使能
        .inst_sram_wen     (inst_sram_wen     ), // 指令存储器写使能
        .inst_sram_addr    (inst_sram_addr_v  ), // 指令存储器地址（虚拟地址）
        .inst_sram_wdata   (inst_sram_wdata   ), // 指令存储器写数据
        .inst_sram_rdata   (inst_sram_rdata   ), // 指令存储器读数据
        .data_sram_en      (data_sram_en      ), // 数据存储器使能
        .data_sram_wen     (data_sram_wen     ), // 数据存储器写使能
        .data_sram_addr    (data_sram_addr_v  ), // 数据存储器地址（虚拟地址）
        .data_sram_wdata   (data_sram_wdata   ), // 数据存储器写数据
        .data_sram_rdata   (data_sram_rdata   ), // 数据存储器读数据
        .debug_wb_pc       (debug_wb_pc       ), // 写回阶段的PC值
        .debug_wb_rf_wen   (debug_wb_rf_wen   ), // 写回阶段的寄存器写使能信号
        .debug_wb_rf_wnum  (debug_wb_rf_wnum  ), // 写回阶段的寄存器写地址
        .debug_wb_rf_wdata (debug_wb_rf_wdata )  // 写回阶段的寄存器写数据
    );

    // 实例化内存管理单元（MMU）用于指令地址转换
    mmu u0_mmu(
        .addr_i (inst_sram_addr_v ), // 虚拟地址输入（指令地址）
        .addr_o (inst_sram_addr   )  // 物理地址输出（连接到指令存储器）
    );

    // 实例化内存管理单元（MMU）用于数据地址转换
    mmu u1_mmu(
        .addr_i (data_sram_addr_v ), // 虚拟地址输入（数据地址）
        .addr_o (data_sram_addr   )  // 物理地址输出（连接到数据存储器）
    );

endmodule
