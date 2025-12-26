# Digital Logic 2025 Fall Project Architecture Report(Final Version)

**Authors:**
- 陈彦桥(Yanqiao Chen, 12412115), 负责顶层模块、输入、随机数生成、矩阵覆盖逻辑、随机选择、卷积模块的开发
- 蒋言(Yan Jiang, 12410337)：负责计算模块以及下属计算模块的开发
- 侯栋升(Dongsheng Hou, 12410421)：负责BRAM和Matrix Manager的开发

**贡献比1：1：1**

## 开发计划日程安排和实施情况，版本修改记录

### 开发计划日程安排

项目开发从初始规划开始，逐步实现各个模块。以下是主要阶段：

- **初始阶段**：项目立项，确定基本架构，使用DRAM存储。编写基本的储存模块，通过测试debug储存功能。
- **中期阶段**：实现UART通信、按键消抖、基本模式切换，实现主要模式控制的自动机以及数据多路选择器。
- **后期阶段**：实现矩阵输入、存储和计算功能，发现综合问题和时序违例，重构为BRAM存储。
- **最终阶段**：完善所有计算模式、设置模式、错误处理，初步开发了GUI但是尚未完善，因此不提交检查。

### 实施情况

项目基本完成所有要求，并实现了若干bonus功能，包括卷积操作、倒计时错误恢复、随机生成等。GUI有框架但未完全连接。

### 版本修改记录

GitHub仓库链接：https://github.com/SUSTech-Digital-Logic-Project-Team/Digital-Logic-Fall-2025-Project-Matrix-Calculator

提交记录（部分）：
- ae04f1c Merge pull request #28 from hotteano/main
- 7d797e5 Merge branch 'main' into main
- 31489e5 update
- 72e5d1f update
- 38d3476 update
- e5bf7ca update
- e6a417d update
- 15bd659 update
- 6817a1a update
- 679961f Okay this is the end
- ... (更多提交见仓库)，共108次commit，pull request共29个

## 项目架构设计说明

基于提交的架构设计文档，改进后的最终实现方案如下：

**原有架构内容和内部实现保持不变**

## 输出对齐和参数配置设计思路

### 输出对齐

在显示和UART输出中，实现输出对齐通过在数字间添加空格，并在行列分隔时发送换行符。计数器维护当前行数据，当一行显示完毕时发送换行符（ASCII码10）。

其实现主要通过若干子状态寄存器实现格式化输出，其核心在于通过读取Matrices Manager中的矩阵维度信息，通过维护计数器，检查边界来实现格式化输出。没有与更多其它模块有数据交换。

### 参数配置

设置模式允许用户通过UART自定义参数，包括最大矩阵维度、最大数值、同一维度最大矩阵数量、倒计时设置。FPGA复位后参数初始化为默认值，用户可在运行时修改。与周边模块的关系：设置模式与顶层模块交互，更新config寄存器；顶层模块将这些参数传递给各子模块，如计算模式、生成模式等，用于限制输入范围和操作。

## 应用开发

项目实现了GUI应用（matrix_calculator_gui.py，位于github仓库，此部分代码由于未完成，故未提交）。

## 输入和输出接口

The input port and output port is listed as follows: 

**INPUT:**

- The clock: 1 bit width
- Reset button: 1 bit width
- DIP switch: 3 bits width, SW2 as MSB, SW0 as LSB, used for choosing different modes
- Confirm button: 1 bit width, used for confirm main mode selection
- Go back button: 1 bit width, used for go back to main menu
- UART Receiver: 1 bit width, used for receiving data from PC


**OUTPUT:**

- UART Transimitter: 1 bit width, used for transimitting data to PC
- 7-Seg LED: 7 bits width, used for displaying information like mode, opertion type, error code, counting time...
- LED: 4 bits width, LD3 as MSB, LD0 as LSB, used for indicating working, error type and so on.
- 7-Seg LED selection: 2 bits width, used for selecting 7-Seg LED

![描述文本](/Graph/1.png)  


## 整体架构概览

The Architecture of this project is purposed as follow: 

**A Global View:**
- The Top Module
- The Memory Controller
- Processing Modes
- Display Controller
- UART Module
- Tool Kit

**架构框图示意**
```
┌─────────────┐
│    UART     │◄──────► EGO1 UART PORT
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
    │  │  ├─────────────┤  │ Pool │  │ │
    │  │  │ Setting M.  │ ─┘      └──┼─┤
    │  │  └─────────────┘            │  │
    │  └─────────────────────────────┘  │
    │                                   │
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
    │                                   │
    │  ┌──────────────────────────────┐ │
    │  │ Control Logic & Multiplexers │ │
    │  │ • Allocation FSM             │ │
    │  │ • Address routing            │ │
    │  │ • R/W arbitration            │ │
    │  └──────────────────────────────┘ │
    └───────────────────────────────────┘
            │                   │
            ▼                   ▼
    ┌─────────────┐      ┌──────────────┐
    │   LFSR RNG  │      │ Display Ctrl │
    │   16 bits   |      |  7-Seg+LEDs  |
     random number|      |              |
    └─────────────┘      └──────────────┘
```
**架构和数据流示意图**
![描述文本](/Graph/2.png)  

### The Top Module

顶层模块包含：

| Name | Input | Output | Usage|
|:--------------:|:---:|:---:|:---:|
|Matrix Calc Top |clk, rst_n, dip_sw[2:0], btn_confirm, btn_back, uart_rx| uart_tx, seg_display[6:0], led_status[3:0], seg_select[1:0]| Top module

### The Memory Controller
| Name | Input | Output | Usage|
|:--------------:|:---:|:---:|:---:|
|Memory Pool| clk, rst_n, a_n, a_we, a_addr[ADDR_WIDTH-1:0], a_din[DATA-1:0], b_en, b_addr[ADDR_WIDTH-1:0]| a_dout[ADDR_WIDTH-1:0], b_dout[DATA_WIDTH-1:0]| Storing Data
|Matrix Manager| clk, rst_n, alloc_req, alloc_m[3:0], alloc_n[3:0], commit_req, commit_slot[3:0], commit_m[3:0], commit_n[3:0], commit_addr[11:0], query_clot[3:0] | alloc_slot[3:0], alloc_addr[11:0], alloc_valid, query_m[3:0], query_n[3:0], query_addr[11:0], query_element_count[7:0], total_matrix_count[7:0]| Managing Matrices|

### Process Modes

| Name | Input | Output | Usage|
|:--------------:|:---:|:---:|:---:|
|Compute Mode| clk (1 bit), rst_n (1 bit), mode_active (1 bit), config_max_dim [3:0], dip_sw [2:0], btn_confirm (1 bit), rx_data [7:0], rx_done (1 bit), tx_busy (1 bit), total_matrix_count [7:0], query_valid (1 bit), query_m [3:0], query_n [3:0], query_addr [11:0], query_element_count [7:0], mem_rd_data [15:0]| clear_rx_buffer (1 bit), tx_data [7:0], tx_start (1 bit), selected_op_type [3:0], query_slot [3:0], mem_rd_en (1 bit), mem_rd_addr [11:0], error_code [3:0], sub_state [3:0]| Performs matrix computations like addition, multiplication|
|Generate Mode| clk (1 bit), rst_n (1 bit), mode_active (1 bit), config_max_dim [3:0], config_max_value [3:0], random_value [3:0], rx_data [7:0], rx_done (1 bit), tx_busy (1 bit), alloc_slot [3:0], alloc_addr [11:0], alloc_valid (1 bit)| clear_rx_buffer (1 bit), tx_data [7:0], tx_start (1 bit), alloc_req (1 bit), commit_req (1 bit), commit_slot [3:0], commit_m [3:0], commit_n [3:0], commit_addr [11:0], mem_wr_en (1 bit), mem_wr_addr [11:0], mem_wr_data [15:0], error_code [3:0], sub_state [3:0]| Generates matrices with random or predefined values|
|Input Mode| clk (1 bit), rst_n (1 bit), mode_active (1 bit), config_max_dim [3:0], config_max_value [3:0], rx_data [7:0], rx_done (1 bit), tx_busy (1 bit), alloc_slot [3:0], alloc_addr [11:0], alloc_valid (1 bit), mem_rd_data [15:0]| clear_rx_buffer (1 bit), tx_data [7:0], tx_start (1 bit), alloc_req (1 bit), alloc_m [3:0], alloc_n [3:0], commit_req (1 bit), commit_slot [3:0], commit_m [3:0], commit_n [3:0], commit_addr [11:0], mem_wr_en (1 bit), mem_wr_addr [11:0], mem_wr_data [15:0], mem_rd_en (1 bit), mem_rd_addr [11:0], error_code [3:0], sub_state [3:0]| Receives matrix data from UART and manages memory allocation|
|Setting Mode| clk (1 bit), rst_n (1 bit), mode_active (1 bit), rx_data [7:0], rx_done (1 bit), tx_busy (1 bit)| clear_rx_buffer (1 bit), tx_data [7:0], tx_start (1 bit), config_max_dim [3:0], config_max_value [3:0], config_matrices_per_size [3:0], error_code [3:0], sub_state [3:0]| Configures operational settings|

### Display Controller

| Name | Input | Output | Usage|
|:--------------:|:---:|:---:|:---:|
|Display Control| clk (1 bit), rst_n (1 bit), matrix_data [7:0], mode [2:0]| seg_display [6:0], seg_select [1:0], led_status [3:0]| Manages display of matrix data and status indicators|

### UART Module

| Name | Input | Output | Usage|
|:--------------:|:---:|:---:|:---:|
|UART Receiver| clk (1 bit), rst_n (1 bit), uart_rx (1 bit)| received_data [7:0]| Receives data from PC|
|UART Transmitter| clk (1 bit), rst_n (1 bit), data_to_send [7:0]| uart_tx (1 bit)| Sends data to PC|
|UART Module| clk (1 bit), rst_n (1 bit), uart_rx (1 bit), data_to_send [7:0]| uart_tx (1 bit), received_data [7:0]| Combines UART Receiver and Transmitter functionalities|

### Tool kit

| Name | Input | Output | Usage|
|:--------------:|:---:|:---:|:---:|
|matrix package|NO | NO | Some Macros settings, like clock frequency|
|LSFR Random number generator|clk, rst_n, max_value[3:0]|random_value[3:0]| For generating psuedorandom number, by using polynomial|

## The FSM

项目中主要的状态机包含：

- IDLE, MODE_INPUT, MODE_COMPUTE, MODE_GENERATE, MODE_SETTING, MODE_DISPLAY
- Input Mode: IDLE, PARSE_M, PARSE_N, CHECK_DIM, WAIT_ALLOC, PARSE_DATA, FILL_ZEROS, COMMIT, DISPLAY_MATRIX, DONE, ERROR
- Display Mode: IDLE, SHOW_COUNT, WAIT_SELECT, READ_DATA, CONVERT_DATA, SEND_DIGITS, DONE
- Generate Mode: IDLE, WAIT_M, WAIT_N, ALLOC, GEN_DATA, COMMIT, DONE
- Compute Mode: IDLE, SELECT_OP, SELECT_MATRIX, EXECUTE, SEND_RESULT, DONE

### 状态机示意图

**Top**
![描述文本](/Graph/top.png) 

**Modules**
![描述文本](/Graph/3.png) 

## 开源和AI使用

### 开源声明

本项目使用MIT协议开源，所有代码和文档可在GitHub仓库获取。

### AI使用声明和开源代码使用声明

- AI提供BRAM优化建议，有效避免LUT综合爆炸。
- AI局限性：在复杂Verilog中，AI常在无关处过度检查，输出需人工review和debug。
- 其中，input mode部分代码由上一版本（无BRAM版本）使用AI完全重构而来，generate mode由input mode复制和手动修改而来。内存管理（BRAM Pool和Matrices Manager由AI主要编写）主要参考AI编写，例如分配逻辑和覆盖逻辑。计算模块由Yan Jiang整体编写，然后通过AI进行细节调优，尤其是对一些编写错误、状态重复和寄存器冗余进行了调整，并且由完全整合在Compute Mode里面变成了模块化为单独模块。UART模块为课程提供的模块，我们加入了UART Module方便其他模块调用。
- 随机数生成器（线性反馈位移寄存器）由大模型提供，我们上网查找了资料，对其有了一定的了解。
- Button Debounce主要由AI提供（此时实验课尚未讲授，因此我们查找资料并用AI生成了一份），并且在后续的实验课上进行了完善。
- Setting Mode设置思路主要由小组成员提供，并且交由AI搭建状态机框架，然后根据需要进行调整。
- 限制文件为手动编写，无AI生成内容。
- 本项目主要使用的开源代码即课程提供的UART模块，没有使用其它仓库代码。
- 本项目许多比较困难的地方由Claude Opus 4.5编写，其它部分包含了Gemini Pro 2.5, Gemini Pro 3, GPT-5.1-Codex-Max, GPT-4o, Grok Code Fast, Claude Sonnet 4.5, Claude Haiku 4.5。

## 思考与总结

本次项目，我们大量采用AI生成重复代码-人工调优debug模式，尤其在状态机设置、多路选择和模块连接中。这些模块编写起来相当枯燥单调，因此我们普遍使用了Prompt工程来生成这些代码。另外，尤其是在Compute Mode中，其中包含了大量格式化输出所需要的代码，我们大部分都使用AI来生成这些重复且冗余的代码。

在AI时代，我们往往会因为Vibe Coding所带来的方便而陷入其中。但是实际上，过度的Vibe Coding往往会导致一个项目变成完全的屎山的速度大大加快。AI往往会添加大量不需要的冗余功能，并且可能埋下若干在前期设计中完全意想不到的问题。尤其是在当前，AI尚不具备设计高度复杂系统的能力，因此需要工程师对于AI生成的代码更加谨慎和小心，必须要完整地理解AI所写的代码的功能、实现方法和其与其它部分的交互。一个可以借鉴的经验是，不要给AI提供太长的上下文，最好是让AI修改局部功能，或者生成重复的代码，而不要将整个工程交给AI来处理，这样往往会导致不必要的麻烦。

### AI辅助开发导致的问题：上下文理解混乱

例如，我们在开发过程中遇到了这样的问题：AI在前期设计的时候，使用了5位位宽的二进制数来表示状态，但是到了后期，由于模块功能更加复杂，状态迅速增加到了100+个，此时，AI仍然使用5位的位宽来标记状态（不知为何，可能受到了上下文干扰），因此导致了我们在开发过程中需要仔细地去查找到底是哪个地方出了问题。最终我们将这个问题检查出来并进行了修复。

另一个例子是，我们通过AI来去除一些不需要的代码（例如，我们在前期编写了display模式，但是后续放弃了开发，需要删除），但是AI在匹配了所有应该删除项之后，继续删除了很多必要的功能，这导致我们不得不回滚代码以保证代码可以运行。此类情况在无需付费的免费模型尤其常见（例如GPT-4o和Grok Code Fast）

这表明，AI辅助编程仍然无法很好地实现复杂功能，若要实现，则需要非常详细的Prompt。有时候，清晰地描述一个需求比自己直接编写还要困难，因为需要更加谨慎的检查AI的修改是否会影响到其它部分的正常工作。

### 一些比较好的交互例子

**如下是在进行矩阵覆盖开发的对话。**

-------

**Human:** 可以保存一个指针，指向每一个维度优先替换的那个矩阵，matrix_manager的分配逻辑增加：若超出顶层模块中的“同一维度矩阵限制”，那么直接返回指针指向的那个矩阵，然后将指针指向下一个同一维度的矩阵（由于矩阵在内存上先后被分配，因此只需要向后查找第一个同维度的矩阵），如果指针指向的同一维度矩阵数超出限制，则回到第一个。

**Agent:**

(此处省略若干修改，AI正确地修改了逻辑，并且使用了全局时间戳记录矩阵的录入顺序)

- Added per-dimension cap support in matrix_manager_optimized.v: tracks per-size counts and replacement pointers, returns the pointer slot for overwrite when count hits dim_limit_per_size, advances pointer to the next same-dimension matrix, and keeps counts/pointers in sync on commit. New helper find_next_same_dim wraps within slots.
- Introduced per-dimension tracking tables (1024 entries for 5-bit m/n) and reset them; kept existing address reuse so overwrites use the original start_addr.
- Wired config_matrices_per_size into the manager via new port dim_limit_per_size in matrix_calculator_top_optimized.v.
Next steps: build/sim to confirm synthesis passes and that allocation+commit flows from input/generate/compute still behave as expected under dimension caps.

--------

如上，我们发现，如果需要Agent正确地修改文件，必须要提供明确的上下文（上文中，我们明确提供了Matrix Manager文件，并且要求其修改分配逻辑），并且指出你的实现思路，最好是分步叙述，并且要给出明确的对象描述，不能够模糊，否则AI可能根据其想法通过其它的方式进行实现，这大大增加了理解成本和debug的成本。

**如下是在进行错误状态倒计时开发的对话。**

-------

**Human:** 显然，如果我们要显示一个两位数倒计时，我们就不能只选中一个数码管，我们应该在两个数码管之间高频切换（例如使用一个两位独热码从而显示例如15之类的倒计时）

**Agent:**

(此处省略若干修改，AI正确地修改了逻辑，并且使用了全局时间戳记录矩阵的录入顺序)

明白了，您需要将 count_down_select 从单一的使能信号改为一个2位的独热码，用于在两个数码管之间高频切换，以显示两位数的倒计时（如15秒）。

让我先查看 display_ctrl 模块了解当前的显示控制逻辑：

display_ctrl.v

现在我理解了整体结构。当前 countdown_val 是4位的，只能显示0-9。需要：

将 countdown_val 扩展为支持两位数（5-15）
在 display_ctrl 中添加两个数码管的扫描逻辑用于倒计时显示
将 count_down_select 改为2位独热码输出
已编辑
matrix_calculator_top_optimized.v+25-24
现在修改 display_ctrl 模块，添加两位数倒计时显示的扫描逻辑：

现在需要调整扫描计数器的声明顺序，因为 scan_cnt 在倒计时逻辑中被引用，但是它的声明在后面。让我检查一下文件的当前状态：display_ctrl.v

需要将 scan_cnt 的声明移到倒计时逻辑之前：

现在删除重复的 scan_cnt 声明和 always 块：

display_ctrl.v

现在验证所有文件是否有错误：

display_ctrl.vmatrix_calculator_top_optimized.v

修改完成！让我总结一下本次更改：

修改总结
1. matrix_calculator_top_optimized.v
count_down_select 从 1 位改为 2 位输出（独热码）
删除了固定的 assign count_down_select = 1'b1，改由 display_ctrl 模块驱动
countdown_val 从 4 位扩展为 5 位，支持 5-15 的两位数显示
countdown_reg 同样扩展为 5 位
在 display_ctrl 实例化中添加了 .count_down_select(count_down_select) 端口连接
2. display_ctrl.v
countdown_val 输入从 4 位扩展为 5 位
新增 count_down_select 2 位独热码输出端口
添加了 countdown_tens（十位）和 countdown_ones（个位）的计算逻辑
添加了 digit_to_seg 函数用于数字到七段显示的编码
倒计时显示使用与主显示相同的 scan_cnt[16] 进行高频切换：
scan_cnt[16] == 0：选中左侧数码管（count_down_select = 2'b10），显示十位
scan_cnt[16] == 1：选中右侧数码管（count_down_select = 2'b01），显示个位
十位为 0 时不显示（避免显示 "05" 而是显示 " 5"）
无错误时 count_down_select = 2'b00（关闭倒计时数码管）
--------

如上，我们可以看到，我们的提示词并不复杂，但是Claude Opus 4.5很好的修改了代码，并且给出了详细的代码注释。这表明，Claude Opus 4.5的代码能力非常强。我们在实际体验中也感受得到了这一模型的效率和准确率。这表明，在编写过程中，选择正确的代码模型也是很重要的。许多同学可能无法使用Claude系列模型，在项目开发中可能就会因为许多模型（尤其是GPT的代码模型）的胡乱输出导致整个项目不得不回滚。

### 总结

总而言之，我们在本次的项目开发中学到了如何搭建一个完整的小项目，并且从AI的代码中学习了很多Verilog相关的知识（例如，强制综合器使用BRAM，强制综合器不优化掉某一个变量），同时也学会了很多Debug方面的知识，例如编写测试文件，设置断点测试并上板通过串口进行调试，等等。最终我们也顺利完成了本次Project的开发，实现了绝大部分的功能，并且实现了参数设置、输出对齐和卷积等bonus功能。

## 对课程的建议

我认为，Project后续的设计应该聚焦于FPGA上计算本身的优化，而不是主要在输入输出、存储等细节上。首先，Memory在课程中比较后面才开始讲到，并且比较浅显，对于Project早期开发造成了一定困扰。其次，AI很容易能够编写出类似的功能，因此此功能很可能无法反映出学生对于数字逻辑课程本身的学习程度。

一个建议是，下次的Project中，应该将“功能性”的内容转向“性能”方向，例如，通过PE阵列加速运算、编写快速傅里叶卷积、快速矩阵乘法等算法，以及通过Vivado本身的各类优化器对FPGA生成的电路进行优化，甚至在FPGA上实现神经网络等等，这或许是在深度学习时代的一种探索方向。



