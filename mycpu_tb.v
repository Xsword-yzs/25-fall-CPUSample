/*------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Copyright (c) 2016, Loongson Technology Corporation Limited.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this 
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation and/or
   other materials provided with the distribution.

3. Neither the name of Loongson Technology Corporation Limited nor the names of
   its contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL LOONGSON TECHNOLOGY CORPORATION LIMITED BE LIABLE
TO ANY PARTY FOR DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------
------------------------------------------------------------------------------*/
`timescale 1ns / 1ps

// 定义宏，用于配置测试环境和连接信号
`define TRACE_REF_FILE "../../../../../../../cpu132_gettrace/golden_trace.txt" // 参考跟踪文件路径
`define CONFREG_NUM_REG      soc_lite.confreg.num_data // 配置寄存器编号
`define CONFREG_OPEN_TRACE   soc_lite.confreg.open_trace // 配置寄存器打开跟踪功能
`define CONFREG_NUM_MONITOR  soc_lite.confreg.num_monitor // 配置寄存器监视数字
`define CONFREG_UART_DISPLAY soc_lite.confreg.write_uart_valid // 配置寄存器UART显示使能
`define CONFREG_UART_DATA    soc_lite.confreg.write_uart_data // 配置寄存器UART数据
`define END_PC 32'hbfc00100 // 测试结束的程序计数器（PC）地址

// 顶层测试模块
module tb_top( );
    reg resetn; // 复位信号，低电平有效
    reg clk;     // 时钟信号

    // GPIO 接口信号
    wire [15:0] led;
    wire [1 :0] led_rg0;
    wire [1 :0] led_rg1;
    wire [7 :0] num_csn;
    wire [6 :0] num_a_g;
    wire [7:0] switch;
    wire [3:0] btn_key_col;
    wire [3:0] btn_key_row;
    wire [1:0] btn_step;

    // 默认输入信号赋值
    assign switch      = 8'hff; // 所有开关关闭
    assign btn_key_row = 4'd0;  // 按键行设置为0
    assign btn_step    = 2'd3;  // 步进按钮设置为3

    // 初始化块，设置时钟和复位信号
    initial
    begin
        clk = 1'b0;      // 初始时钟为低电平
        resetn = 1'b0;   // 初始复位为低电平
        #2000;           // 等待2000个时间单位（例如纳秒）
        resetn = 1'b1;   // 释放复位信号
    end

    // 时钟生成，每5个时间单位翻转一次，实现100MHz时钟
    always #5 clk = ~clk;

    // 实例化被测SOC核心模块，设置SIMULATION参数为1
    soc_lite_top #(.SIMULATION(1'b1)) soc_lite
    (
           .resetn      (resetn     ), // 复位信号
           .clk         (clk        ), // 时钟信号

            // ------ GPIO 接口 -------
            .num_csn    (num_csn    ), // 数码管片选信号
            .num_a_g    (num_a_g    ), // 数码管段选信号
            .led        (led        ), // LED灯信号
            .led_rg0    (led_rg0    ), // RGB LED 0
            .led_rg1    (led_rg1    ), // RGB LED 1
            .switch     (switch     ), // 开关输入信号
            .btn_key_col(btn_key_col), // 按键列信号
            .btn_key_row(btn_key_row), // 按键行信号
            .btn_step   (btn_step   )  // 步进按钮信号
    );

    // SOC Lite 信号定义
    // "soc_clk" 表示SOC内部的时钟信号
    // "wb" 表示流水线的写回阶段
    // "rf" 表示CPU内部的寄存器文件
    // "w" 表示写操作
    wire soc_clk;
    wire [31:0] debug_wb_pc;
    wire [3 :0] debug_wb_rf_wen;
    wire [4 :0] debug_wb_rf_wnum;
    wire [31:0] debug_wb_rf_wdata;

    // 从SOC核心模块获取调试信号
    assign soc_clk           = soc_lite.cpu_clk;
    assign debug_wb_pc       = soc_lite.debug_wb_pc;
    assign debug_wb_rf_wen   = soc_lite.debug_wb_rf_wen;
    assign debug_wb_rf_wnum  = soc_lite.debug_wb_rf_wnum;
    assign debug_wb_rf_wdata = soc_lite.debug_wb_rf_wdata;

    // 根据写使能信号，筛选有效的写回数据
    // 每个字节只有在对应的写使能位为1时，才有效
    wire [31:0] debug_wb_rf_wdata_v;
    assign debug_wb_rf_wdata_v[31:24] = debug_wb_rf_wdata[31:24] & {8{debug_wb_rf_wen[3]}};
    assign debug_wb_rf_wdata_v[23:16] = debug_wb_rf_wdata[23:16] & {8{debug_wb_rf_wen[2]}};
    assign debug_wb_rf_wdata_v[15: 8] = debug_wb_rf_wdata[15: 8] & {8{debug_wb_rf_wen[1]}};
    assign debug_wb_rf_wdata_v[7 : 0] = debug_wb_rf_wdata[7 : 0] & {8{debug_wb_rf_wen[0]}};

    // 打开参考跟踪文件
    integer trace_ref;
    initial begin
        trace_ref = $fopen(`TRACE_REF_FILE, "r"); // 以只读模式打开参考跟踪文件
    end

    // 获取参考结果，在falling edge（下降沿）时读取
    reg        trace_cmp_flag;
    reg        debug_end;

    reg [31:0] ref_wb_pc;
    reg [4 :0] ref_wb_rf_wnum;
    reg [31:0] ref_wb_rf_wdata_v;

    // 在SOC时钟的上升沿读取参考跟踪文件中的数据
    always @(posedge soc_clk)
    begin
        #1; // 延迟1个时间单位，确保数据稳定
        if(|debug_wb_rf_wen && debug_wb_rf_wnum != 5'd0 && !debug_end && `CONFREG_OPEN_TRACE)
        begin
            trace_cmp_flag = 1'b0; // 重置比较标志
            while (!trace_cmp_flag && !($feof(trace_ref)))
            begin
                // 从参考跟踪文件中读取PC、寄存器写地址和写数据
                $fscanf(trace_ref, "%h %h %h %h", trace_cmp_flag,
                        ref_wb_pc, ref_wb_rf_wnum, ref_wb_rf_wdata_v);
            end
        end
    end

    // 比较参考结果与实际结果，在上升沿时进行
    reg debug_wb_err;
    always @(posedge soc_clk)
    begin
        #2; // 延迟2个时间单位，确保数据稳定
        if(!resetn)
        begin
            debug_wb_err <= 1'b0; // 复位时清除错误标志
        end
        else if(|debug_wb_rf_wen && debug_wb_rf_wnum != 5'd0 && !debug_end && `CONFREG_OPEN_TRACE)
        begin
            // 如果PC、写地址或写数据不匹配，记录错误
            if (  (debug_wb_pc !== ref_wb_pc) ||
                  (debug_wb_rf_wnum !== ref_wb_rf_wnum) ||
                  (debug_wb_rf_wdata_v !== ref_wb_rf_wdata_v) )
            begin
                // 显示错误信息
                $display("--------------------------------------------------------------");
                $display("[%t] Error!!!",$time);
                $display("    reference: PC = 0x%8h, wb_rf_wnum = 0x%2h, wb_rf_wdata = 0x%8h",
                          ref_wb_pc, ref_wb_rf_wnum, ref_wb_rf_wdata_v);
                $display("    mycpu    : PC = 0x%8h, wb_rf_wnum = 0x%2h, wb_rf_wdata = 0x%8h",
                          debug_wb_pc, debug_wb_rf_wnum, debug_wb_rf_wdata_v);
                $display("--------------------------------------------------------------");
                debug_wb_err <= 1'b1; // 设置错误标志
                #40;
                $finish; // 结束仿真
            end
        end
    end

    // 监控数码管显示
    reg [7:0] err_count; // 错误计数
    wire [31:0] confreg_num_reg = `CONFREG_NUM_REG; // 从配置寄存器读取的数字
    reg  [31:0] confreg_num_reg_r; // 注册的数字，用于比较

    // 在SOC时钟的上升沿监控数字显示
    always @(posedge soc_clk)
    begin
        confreg_num_reg_r <= confreg_num_reg; // 注册当前数字
        if (!resetn)
        begin
            err_count <= 8'd0; // 复位时错误计数清零
        end
        else if (confreg_num_reg_r != confreg_num_reg && `CONFREG_NUM_MONITOR)
        begin
            // 检查低字节是否按顺序递增
            if(confreg_num_reg[7:0] != confreg_num_reg_r[7:0] + 1'b1)
            begin
                $display("--------------------------------------------------------------");
                $display("[%t] Error(%d)!!! Occurred in number 8'd%02d Functional Test Point!",$time, err_count, confreg_num_reg[31:24]);
                $display("--------------------------------------------------------------");
                err_count <= err_count + 1'b1; // 错误计数增加
            end
            // 检查高字节是否按顺序递增
            else if(confreg_num_reg[31:24] != confreg_num_reg_r[31:24] + 1'b1)
            begin
                $display("--------------------------------------------------------------");
                $display("[%t] Error(%d)!!! Unknown, Functional Test Point numbers are unequal!",$time,err_count);
                $display("--------------------------------------------------------------");
                $display("==============================================================");
                err_count <= err_count + 1'b1; // 错误计数增加
            end
            else
            begin
                // 功能测试点通过
                $display("----[%t] Number 8'd%02d Functional Test Point PASS!!!", $time, confreg_num_reg[31:24]);
            end
        end
    end

    // 监控测试进度
    initial
    begin
        $timeformat(-9,0," ns",10); // 设置时间格式，单位为纳秒
        while(!resetn) #5; // 等待复位完成
        $display("==============================================================");
        $display("Test begin!"); // 显示测试开始信息

        #10000; // 等待10000个时间单位
        while(`CONFREG_NUM_MONITOR)
        begin
            #10000; // 每10000个时间单位检查一次
            $display ("        [%t] Test is running, debug_wb_pc = 0x%8h",$time, debug_wb_pc); // 显示测试运行状态
        end
    end

    // 模拟串口打印
    wire uart_display;
    wire [7:0] uart_data;
    assign uart_display = `CONFREG_UART_DISPLAY; // UART显示使能信号
    assign uart_data    = `CONFREG_UART_DATA;    // UART数据

    // 在SOC时钟的上升沿处理UART数据
    always @(posedge soc_clk)
    begin
        if(uart_display)
        begin
            if(uart_data == 8'hff)
            begin
                ;//$finish; // 如果UART数据为0xFF，结束仿真（当前注释掉）
            end
            else
            begin
                $write("%c", uart_data); // 打印UART数据对应的字符
            end
        end
    end

    // 测试结束逻辑
    wire global_err = debug_wb_err || (err_count != 8'd0); // 全局错误标志
    wire test_end = (debug_wb_pc == `END_PC) || (uart_display && uart_data == 8'hff); // 测试结束条件

    // 在SOC时钟的上升沿检测测试结束
    always @(posedge soc_clk)
    begin
        if (!resetn)
        begin
            debug_end <= 1'b0; // 复位时清除测试结束标志
        end
        else if(test_end && !debug_end)
        begin
            debug_end <= 1'b1; // 设置测试结束标志
            $display("==============================================================");
            $display("Test end!"); // 显示测试结束信息
            #40;
            $fclose(trace_ref); // 关闭参考跟踪文件
            if (global_err)
            begin
                $display("Fail!!! Total %d errors!", err_count); // 显示错误计数
            end
            else
            begin
                $display("----PASS!!!"); // 显示测试通过信息
            end
            $finish; // 结束仿真
        end
    end
endmodule
