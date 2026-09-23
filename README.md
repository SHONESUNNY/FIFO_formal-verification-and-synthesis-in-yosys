# FIFO Formal Verification & Synthesis

This repository contains a SystemVerilog FIFO and a verification/synthesis flow using **Yosys, SymbiYosys (SBY), and Z3**.

## Contents

- [1. Design](#1-design)
- [2. Formal Verification Flow](#2-formal-verification-flow)
- [3. Assume, Assert, Cover](#3-assume-assert-cover)
- [4. Bounded Model Checking](#4-bounded-model-checking)
- [5. Counterexamples](#5-counterexamples)
- [6. Basic FIFO Assertions](#6-basic-fifo-assertions)
- [7. Read/Write Verification](#7-readwrite-verification)
- [8. Assumptions and State Space](#8-assumptions-and-state-space)
- [9. Synthesis with Yosys](#9-synthesis-with-yosys)

---

## 1. Design

The FIFO is a synchronous, parameterized FIFO with:

- Parameterized data width
- Parameterized depth
- Write pointer
- Read pointer
- Occupancy counter
- `full` and `empty` flags
- Memory array
- Read/write enables

Conceptually:

```text
                 +----------------------+
din -----------> |                      |
wr_en ---------> |        FIFO          | ----> dout
rd_en ---------> |                      |
                 |  memory              |
                 |  wr_ptr / rd_ptr     |
                 |  count               |
                 |  full / empty        |
                 +----------------------+
```

An operation is accepted only when the FIFO is able to perform it:

```systemverilog
wire write_accepted = wr_en && !full;
wire read_accepted  = rd_en && !empty;
```

Therefore:

```text
wr_en = 1, full = 1
    -> attempted write, not accepted

rd_en = 1, empty = 1
    -> attempted read, not accepted
```

---

# 2. Formal Verification Flow

The formal flow is:

```text
             FIFO RTL
                |
                v
        formal_fifo.sv
      assumptions/assertions
                |
                v
              Yosys
                |
                v
         SymbiYosys (SBY)
                |
                v
             smtbmc
                |
                v
               Z3
```

Unlike conventional simulation, the formal harness does not need to generate a specific test sequence for unconstrained inputs.

Signals such as:

```systemverilog
logic wr_en;
logic rd_en;
logic [DATA_WIDTH-1:0] din;
```

can be left unconstrained.

The solver then treats them as symbolic values and searches possible input sequences.

Conceptually:

```text
formal solver
     |
     +---- wr_en
     +---- rd_en
     +---- din
             |
             v
           FIFO
             |
             v
        assertions
```

The solver searches for a behavior satisfying all assumptions and violating an assertion.

---

# 3. Assume, Assert, Cover

## `assume`

`assume` constrains the environment.

Example:

```systemverilog
assume (condition);
```

means:

> Only consider behaviors where `condition` is true.

Use assumptions for real environmental restrictions.

Do not use them merely to make a proof easier.

For example, if the environment specification genuinely guarantees that reads are never requested from an empty FIFO, this can be modeled as an assumption. If the FIFO is supposed to tolerate such a request, that behavior should remain in the formal search space.

---

## `assert`

`assert` specifies behavior that the DUT must satisfy.

Example:

```systemverilog
always @(posedge clk) begin
    if (rst_n)
        assert (!(full && empty));
end
```

This means:

> When reset is inactive, `full` and `empty` must never both be `1`.

The assertion does not drive the DUT. It is a property checked against the DUT.

If formal finds a violating behavior:

```text
BMC failed
```

and a counterexample can be generated.

---

## `cover`

`cover` asks formal to find a reachable state or event.

Example:

```systemverilog
always @(posedge clk)
    cover (full);
```

This means:

> Find a legal input sequence that reaches the full state.

For a FIFO, useful reachability goals include:

```systemverilog
cover (empty);
cover (full);
cover (count == 1);
cover (count == DEPTH-1);
cover (read_accepted && write_accepted);
```

Unlike `assert`, `cover` is not a correctness requirement. It asks for a witness trace.

---

# 4. Bounded Model Checking

A typical SBY configuration is:

```text
[options]
mode bmc
depth 5

[engines]
smtbmc z3

[script]
read -formal -sv fifo.sv formal_fifo.sv
prep -top formal_fifo_tb

[files]
fifo.sv
formal_fifo.sv
```

The two `depth` concepts must not be confused.

### FIFO depth

In the RTL:

```systemverilog
parameter DEPTH = 16;
```

means:

```text
FIFO capacity = 16 entries
```

### BMC depth

In SBY:

```text
depth 5
```

means:

```text
explore 5 formal time steps
```

Therefore:

```text
FIFO DEPTH = 16
BMC depth  = 5
```

means a 16-entry FIFO is being explored for only 5 clock steps.

## What BMC asks

BMC asks:

> Is there any behavior, within the selected bound, that violates an assertion?

If a violation is found:

```text
BMC failed
```

If no violation is found:

```text
Status: passed
```

A passing BMC result is bounded. It does not automatically establish correctness for all future time.

---

# 5. Counterexamples

When an assertion fails, SBY may report:

```text
BMC failed!
Assert failed ...
Writing trace to VCD file: engine_0/trace.vcd
Writing trace to Verilog testbench: engine_0/trace_tb.v
Status: failed
```

The counterexample is a concrete sequence of input values and states that demonstrates the assertion failure.

Common generated files include:

```text
engine_0/trace.vcd
engine_0/trace_tb.v
engine_0/trace.yw
engine_0/trace.smtc
```


## Generated replay testbench

Inspect:

```bash
less fifo/engine_0/trace_tb.v
```

or:

```bash
cat fifo/engine_0/trace_tb.v
```

This is a generated simulation-style testbench that can reproduce the formal counterexample.

---

# 6. Basic FIFO Assertions

The first useful properties are simple invariants.

## Full and empty must be mutually exclusive

```systemverilog
always @(posedge clk) begin
    if (rst_n)
        assert (!(full && empty));
end
```

## Empty flag corresponds to count

If `count` is exposed from the FIFO:

```systemverilog
always @(posedge clk) begin
    if (rst_n)
        assert (empty == (count == 0));
end
```

## Full flag corresponds to count

```systemverilog
always @(posedge clk) begin
    if (rst_n)
        assert (full == (count == DEPTH));
end
```

These properties check the control state of the FIFO without requiring a complicated data reference model.

---

# 7. Read/Write Verification

The FIFO's occupancy behavior can be summarized as:

```text
                     READ
                 0          1

WRITE = 0       HOLD       -1
WRITE = 1        +1       HOLD
```

where "write" and "read" mean **accepted operations**.

```systemverilog
wire write_accepted = wr_en && !full;
wire read_accepted  = rd_en && !empty;
```

Therefore the desired behavior is:

```text
write only
    -> count increases by 1

read only
    -> count decreases by 1

read + write
    -> count unchanged

no operation
    -> count unchanged
```

For temporal properties, concurrent SVA can express these relationships naturally when the Yosys/SymbiYosys version supports the required syntax. During initial setup/debugging, simpler procedural assertions are often easier to isolate.

The important timing relationship is:

```text
cycle N:
    operation accepted

cycle N+1:
    updated count reflects that operation
```

For example, a conceptual write-only property is:

```text
write accepted at N
        |
        v
count(N+1) = count(N) + 1
```

A read-only property is:

```text
read accepted at N
        |
        v
count(N+1) = count(N) - 1
```

---

# 8. Assumptions and State Space

It is tempting to add assumptions simply to reduce solver runtime.

The correct rule is:

```text
ASSUMPTION = real environmental restriction
```

not:

```text
ASSUMPTION = anything that makes the proof easy
```

For example, this can be legitimate if it is part of the interface specification:

```systemverilog
assume (empty -> !rd_en);
```

But it is inappropriate if the DUT itself is supposed to handle a read request while empty.

An invalid or contradictory assumption can make the formal problem unsatisfiable:

```text
Assumptions are unsatisfiable!
```

That result means there may be no legal behavior left for the solver to explore.

---

# 9. Synthesis with Yosys

Formal verification and synthesis are separate flows.

A basic generic synthesis script is:

```tcl
read_verilog -sv fifo.sv
hierarchy -top fifo

proc
memory
opt
techmap
opt
clean

write_verilog -noattr fifo_netlist.v

stat
```

Run it with:

```bash
yosys synth.ys
```

This produces:

```text
fifo_netlist.v
```

and the `stat` command reports the synthesized cells.

## What synthesis does

A rough transformation is:

```text
RTL
 |
 | proc
 v
processes -> registers / muxes / logic
 |
 | memory
 v
memory representation
 |
 | opt
 v
simplification and optimization
 |
 | techmap
 v
technology mapping
 |
 v
netlist
```

The resulting generic netlist may contain:

```text
D flip-flops
MUXes
AND / OR logic
comparators
adders
```

Yosys can optimize the generic representation, but that does not make it a final FPGA implementation.

---

```
#  FIFO SYNTHESISED 
![FIFO Netlist](synthesis/fifo_netlist.png)

This is useful for understanding the logic generated from the RTL.

## FPGA implementation

```text
FIFO RTL
   |
   v
Vivado synthesis
   |
   v
LUT / FF / BRAM mapping
   |
   v
placement and routing
   |
   v
bitstream


# 12. Recommended Workflow

A practical progression is:

```text
1. Confirm the RTL elaborates
        |
2. Run one simple assertion with BMC
        |
3. Add a deliberately false assertion
        |
4. Confirm Z3 produces a counterexample
        |
5. Open the counterexample with GTKWave
        |
6. Add basic FIFO invariants
        |
7. Add cover goals for important states
        |
8. Add read/write count properties
        |
9. Increase BMC depth
        |
10. Move to prove/induction
        |
11. Run synthesis
        |
12. Inspect the synthesized netlist/resource mapping
```

This separates formal-tool setup problems from actual RTL verification problems.

---

## Key Concepts

```text
ASSUME
    -> restrict legal environment behavior

ASSERT
    -> property that the DUT must satisfy

COVER
    -> find a reachable state/event

BMC
    -> bounded search for assertion violations

COUNTEREXAMPLE
    -> concrete trace showing why an assertion fails

PROVE / INDUCTION
    -> attempt to establish correctness beyond a finite bound

YOSYS SYNTHESIS
    -> convert RTL into a generic hardware netlist

FPGA SYNTHESIS
    -> map RTL into device resources such as LUTs,
       flip-flops, and BRAM
```

Formal verification asks:

```text
"Does the RTL satisfy the specified properties?"
```

Synthesis asks:

```text
"What hardware structure does this RTL become?"
```
