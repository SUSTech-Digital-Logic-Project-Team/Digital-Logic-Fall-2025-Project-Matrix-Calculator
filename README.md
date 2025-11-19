# 矩阵计算器 - BRAM优化重构版本

## 项目概述

这是对"基于FPGA的交互式矩阵计算器"项目的完整重构，重点是优化BRAM（块RAM）的使用。通过精心设计的内存管理架构，确保在Xilinx EGO1开发板（Artix-7 FPGA）上的综合时使用BRAM而不是LUT资源。

## 文件清单

### 核心模块
- **bram_memory_pool.v** - BRAM专用内存池
  - 同步读写端口设计
  - 强制BRAM推断属性
  - 12位地址宽度（4K元素）

- **matrix_manager_optimized.v** - 优化的矩阵管理器
  - 元数据存储（分布式RAM）
  - 自动地址分配
  - 组合逻辑查询接口

- **matrix_calculator_top_optimized.v** - 顶层模块
  - 完整的子模块实例化
  - 信号多路选择和路由
  - 主状态机控制

### 通信和外设
- **uart_module.v** - UART收发器（115200 bps）
- **lfsr_rng.v** - LFSR伪随机数生成器
- **display_ctrl.v** - 7段显示和LED控制

### 操作模式模块
- **input_mode.v** - 矩阵输入模式
  - UART接收数据
  - 参数验证
  - BRAM写入

- **generate_mode.v** - 随机矩阵生成
  - 使用LFSR生成数据
  - 自动填充BRAM

- **display_mode.v** - 矩阵显示模式
  - UART输出矩阵内容
  - 多矩阵支持

- **compute_mode.v** - 计算模式框架
  - 矩阵操作执行框架
  - 支持多种运算类型

- **setting_mode.v** - 系统设置模式
  - 配置参数调整
  - 系统初始化

### 配置和工具
- **matrix_pkg.vh** - 系统参数和常量定义包
- **parse_utils.vh** - 数据解析工具函数
- **syntax_check.ps1** - Verilog语法检查脚本
- **create_project.tcl** - Vivado项目创建脚本
- **RESTRUCTURE_GUIDE.md** - 详细重构指南

## 关键改进

### 1. 内存优化
```
原设计：65536元素 × 16位地址（可能使用LUTRAM）
优化后：4096元素 × 12位地址（强制使用BRAM）
```

### 2. BRAM推断保证
```verilog
// 关键属性
(* ram_style = "block" *)  // 用于BRAM内存
(* ram_style = "distributed" *)  // 用于小型存储
```

### 3. 地址宽度统一
- 定义：`define BRAM_ADDR_WIDTH 12`
- 应用：所有地址信号使用12位
- 优势：自动适配所有模块

### 4. 分离的内存策略
- 矩阵数据：BRAM（大容量顺序访问）
- 矩阵元数据：分布式RAM（小容量随机访问）

## 快速开始

### 1. 验证语法（可选但推荐）
```powershell
cd Restructure
.\syntax_check.ps1
```
预期结果：`Status: PASS ✓ - Project ready for synthesis`

### 2. 在Vivado中打开项目

**方法A：使用TCL脚本**
```tcl
vivado -source create_project.tcl
```

**方法B：手动创建**
1. 打开Vivado 2017
2. New Project → 选择Restructure文件夹
3. 添加所有.v和.vh文件作为设计源
4. 设置 `matrix_calculator_top_optimized` 为顶层模块
5. 添加XDC约束文件

### 3. 综合
```tcl
# Vivado tcl控制台
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
```

### 4. 验证BRAM使用
在Vivado中检查：
- Design → Summary
- 查看 "Block RAM/FIFO" 部分
- 应显示 ≥1 个BRAM块

### 5. 实现和生成bitstream
```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
```

## 项目规格

| 参数 | 值 |
|------|-----|
| 目标FPGA | Xilinx Artix-7 (XC7A35T) |
| 开发板 | EGO1 |
| 时钟频率 | 100 MHz |
| UART波特率 | 115200 bps |
| BRAM容量 | 4096个4位元素 |
| 最大矩阵数 | 20个 |
| 最大矩阵维度 | 6×6（可配置） |
| 数据宽度 | 4位（0-15） |

## 架构设计

### 顶层信号流
```
┌─────────────┐
│    UART     │◄──────► EGO1开发板串口
└──────┬──────┘
       │
    ┌──┴────────────────────────────────┐
    │   Matrix Calculator Top (FSM)     │
    │  ┌─────────────────────────────┐  │
    │  │  Mode Multiplexer           │  │
    │  │  ┌─────────────┐            │  │
    │  │  │ Input Mode  │            │  │
    │  │  ├─────────────┤            │  │
    │  │  │ Generate M. │            │  │
    │  │  ├─────────────┤            │  │
    │  │  │ Display M.  │ ─┐         │  │
    │  │  ├─────────────┤  │ BRAM    │  │
    │  │  │ Compute M.  │ ─┼◄────►┌──┼─┤
    │  │  ├─────────────┤  │ Pool  │  │  │
    │  │  │ Setting M.  │ ─┘       └──┼─┤
    │  │  └─────────────┘          │  │
    │  └─────────────────────────────┘  │
    │                                    │
    │  ┌──────────────────────────────┐ │
    │  │ Matrix Manager (Metadata)    │ │
    │  │ ┌────────────────────────┐   │ │
    │  │ │ Directory (20 slots)   │   │ │
    │  │ │ • Valid flags          │   │ │
    │  │ │ • Dimensions (M×N)     │   │ │
    │  │ │ • Start addresses      │   │ │
    │  │ │ • Element counts       │   │ │
    │  │ └────────────────────────┘   │ │
    │  └──────────────────────────────┘ │
    │                                    │
    │  ┌──────────────────────────────┐ │
    │  │ Control Logic & Multiplexers │ │
    │  │ • Allocation FSM             │ │
    │  │ • Address routing            │ │
    │  │ • R/W arbitration            │ │
    │  └──────────────────────────────┘ │
    └────────────────────────────────────┘
            │                   │
            ▼                   ▼
    ┌─────────────┐      ┌──────────────┐
    │   LFSR RNG  │      │ Display Ctrl │
    │  16位伪随机 │      │   7-Seg+LEDs │
    └─────────────┘      └──────────────┘
```

## 主要数据通路

### 写入路径
1. UART接收数据 → input_mode/generate_mode
2. 数据验证 → 错误检查
3. 向matrix_manager请求地址 → alloc_slot + alloc_addr
4. 写入BRAM → mem_wr_en + mem_wr_addr + mem_wr_data
5. 向matrix_manager提交 → commit_req确保元数据一致

### 读取路径
1. 应用（display/compute）查询矩阵 → query_slot
2. matrix_manager返回元数据 → 地址、维度、元素数
3. 通过BRAM读取数据 → mem_rd_addr逐个读取
4. 处理或输出结果

## 综合指导

### Vivado 2017设置
```tcl
# 强制BRAM推断
set_param synth.vivado.isSynthRun true
set_property -name {STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS} -value 1 [get_runs synth_1]

# 验证BRAM使用
report_utilization -file bram_utilization.txt
```

### 预期综合结果
- 逻辑元素：~800-1200 LUT
- 触发器：~600-800 FF
- BRAM块：1-2个（取决于内存配置）
- **关键：BRAM块数 ≥ 1**

## 测试和验证

### 单元测试建议
1. **BRAM功能测试**
   - 写入测试向量 → 读回验证
   - 不同地址写入 → 交错读取

2. **矩阵管理器测试**
   - 分配和提交流程
   - 元数据一致性
   - 地址计算正确性

3. **模式集成测试**
   - 输入一个矩阵 → 显示 → 验证内容
   - 生成矩阵 → 显示
   - 各模式间切换

### 硬件验证
1. 编程EGO1板
2. 打开串口监视器（115200 8-N-1）
3. 通过菜单导航测试
4. 输入/输出矩阵验证
5. 检查显示和LED反馈

## 已知限制

1. **内存容量**：4K元素限制最大矩阵大小
   - 单个最大矩阵：64×64
   - 实际限制由矩阵数量和总容量决定

2. **计算功能**：当前仅实现框架
   - 实际运算需要在compute_mode中补充
   - 请参考原项目的运算模块

3. **同时访问**：单BRAM端口限制
   - 一次只能一个操作
   - 可通过双端口BRAM改进

## 扩展和优化

### 短期改进
1. 实现matrix_multi和transpose运算
2. 添加input/output验证错误处理
3. 完善UART协议文档

### 长期优化
1. 集成Xilinx FIFO IP增加缓冲
2. 实现流水线运算加速
3. 级联多个BRAM块扩展容量
4. 添加DDR3接口支持大型矩阵

## 文档参考

- **RESTRUCTURE_GUIDE.md** - 详细的重构和集成指南
- **原项目README.md** - 项目功能概述
- **Xilinx Vivado手册** - 综合约束和最佳实践

## 许可证

本重构基于原项目，继承原许可证。

## 联系和反馈

如发现问题或有改进建议，请：
1. 检查RESTRUCTURE_GUIDE.md中的故障排除章节
2. 验证文件完整性和语法
3. 检查Vivado消息和警告
4. 参考EGO1开发板用户手册

---

**重构版本**：1.0  
**重构日期**：2025年11月18日  
**Vivado版本**：2017  
**Verilog标准**：IEEE 1364-2005  
**状态**：✓ 语法验证通过，可用于综合  
