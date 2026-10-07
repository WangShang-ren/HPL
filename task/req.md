## 任务
先看：https://www.netlib.org/benchmark/hpl/
源码下载：https://www.netlib.org/benchmark/hpl/
调参说明：https://www.netlib.org/benchmark/hpl/tuning.html
HPL 是用于测试计算性能的线性方程组求解程序。本题要求在本地环境中编译并运行 HPL，通过调整参数获得更好的性能结果。

需要完成的任务：


每组参数至少记录：

N
NB
P x Q
运行命令
运行时间
性能结果
是否通过正确性检查

## HPC问题
### 1. HPL 使用什么编译器？
gcc 是真正执行 C 编译的编译器；mpicc 是 MPI 提供的编译包装器。
### 2.  setup/ 是干什么的？
**回答：**
setup/ 目录用于保存针对不同 硬件、编译器、MPI 和数学库环境 的 HPL 构建配置模板。

例如：
- 编译器选择
- MPI 路径
- BLAS 路径
- 编译参数
- 链接参数
- 优化参数
可以理解为：
setup/ = HPL 针对不同环境准备的构建配置模板。
### 3.为什么需要 MPI， 从哪里来？
**回答：**
进行并行计算通信，提高
MPI 不是 HPL 自己实现的，而是由本地安装的 MPI 实现（MPI implementation） 提供。

常见实现包括：
- Open MPI
- MPICH
- Intel MPI
HPL 通过 mpicc、mpirun 等 MPI 工具使用它。
   本地的MPI库，MPI 是并行计算的通信标准/接口规范；Open MPI、MPICH 等是它的具体实现
### 4. 为什么需要，BLAS 从哪里来？
回答：
BLAS 是 HPL 进行矩阵计算时依赖的基础数学库接口，实际使用的是某个 BLAS 实现。

常见实现包括：
- OpenBLAS
- Intel MKL
- BLIS
- Apple Accelerate
关系可以理解为：
HPL
 ↓
BLAS 接口
 ↓
具体 BLAS 实现
 ├── OpenBLAS
 ├── MKL
 ├── BLIS
 └── Accelerate
### 5.  它用什么构建系统？
    `Makefile
    具体编译总程序
    Makefile.am
    提供了路径
    configure.ac
    提供了一些配置和参数
    setup/
    提供具体对应安装文件
   Autotools + Make
### 6.  它依赖什么？
依赖mpicc,mpi,BLAS,以及cblas_**dgemm**d**trsm**
### 7. 真正运行的程序在哪里？
运行makefile后生成
### 5.   为什么最终链接的时候还要 libmpi？
链接器 
###   Make.Linux_Intel64 是什么？
是我当前环境下对应的安装程序，安装什么？与makefile的区别是什么
### 当前这个配置为什么不能直接使用？
  还是源码
### HPL_dgemm 最终会调用什么？
### 最终应该产生什么可执行文件？
    我认为应该产生exe文件

## 命令
```bash
(base) user@DESKTOP-J1MSR9D:~/HPC/hpl$ find libmpi
find: ‘libmpi’: No such file or directory
```
## 提问
啥是MKL



## 优化
面对一个陌生 HPC 项目，我应该如何自己侦察、定位、理解、编译、运行

setup/
放的是不同平台的编译配置

Make.Linux_Intel64
Make.Linux_ATHLON_CBLAS
Make.FreeBSD_PIV_CBLAS
HPL 不是一个 g++ xxx.cpp 就能编译的项目，它有自己的构建系统，而且不同平台/BLAS/MPI 组合需要不同配置。”


## 流程
陌生项目
   ↓
看目录
   ↓
环境侦察：
找 README / INSTALL / Makefile / CMakeLists / pyproject
找出 HPL 使用的 MPI、BLAS、编译器和最终链接方式。

判断构建系统
   ↓
找依赖
   ↓
找入口
   ↓
找配置
构建系统 编译
运行；程序执行链：作图
   ↓
验证
   ↓
profiling
   ↓
优化


撰写报告；

include/hpl_blas.h

HPL_dgemm
HPL_dtrsm
HPL_dgemv
HPL_dger

HPL 的计算核心并不是自己实现所有矩阵运算，而是通过 BLAS。

grep -RInE 'dgemm|dtrsm|dgemv|dger|dswap' src include