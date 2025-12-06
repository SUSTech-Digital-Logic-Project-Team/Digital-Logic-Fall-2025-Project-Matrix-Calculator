# 矩阵计算器 on FPGA

## 项目概述

本项目为对于上一个使用LUT进行储存的版本的BRAM优化版本，由于上一次用LUT综合的时候LUT爆炸了，因此进行了完全重构，使用BRAM储存地址，并且通过Matrix_Manager进行取址，然后通过memory pool访问储存的矩阵。项目基于Verilog 2001标准开发，使用Vivado 2017和Vivado 2022两个版本进行测试、综合。本项目基于Xilinx Artix-7 FPGA工作。

## TODOs 

- 将LUT储存变成用BRAM存储 √
- 实现主模式、子模式转换 √
- 按键消抖 √
- 实现UART通信 √
- 实现输入矩阵并存储 √
- 实现访问矩阵（通过BRAM）√
- 实现随机生成模式 √
- 实现计算模式和若干计算类型 √（除了卷积）
- 完善设置模式和展示模式（这个不要求，但是方便阅读，可以显示目前存储的所有矩阵）
- 实现错误输入倒计时+再次正确输入恢复功能 √

## 文件清单

### 核心模块
- **bram_memory_pool.v** - BRAM专用内存池
  - 同步读写端口设计
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
- **uart_rx.v, uart_tx.v** - UART收发组件
- **lfsr_rng.v** - LFSR伪随机数生成器（For Generate Mode）
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

### 配置和工具（不要调这个包里的参数！会发生不幸）
- **matrix_pkg.vh** - 系统参数和常量定义包
  
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

## 主要数据通路

### 写入路径
1. UART接收数据 → input_mode/generate_mode
2. 数据验证 → 错误检查（如有错误，进入倒计时）
3. 向matrix_manager请求地址 → alloc_slot + alloc_addr
4. 写入BRAM → mem_wr_en + mem_wr_addr + mem_wr_data
5. 向matrix_manager提交 → commit_req确保元数据一致

### 读取路径
1. 应用（display/compute）查询矩阵 → query_slot
2. matrix_manager返回元数据 → 地址、维度、元素数
3. 通过BRAM读取数据 → mem_rd_addr逐个读取
4. 处理或输出结果

## 许可证

本项目采用MIT协议。

