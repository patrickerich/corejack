# CV32E40X first accepted instruction fetch after boot is `boot_addr_i + 4`

## Summary

When integrating CV32E40X through its documented instruction interface, the first
accepted instruction fetch after reset appears to use `boot_addr_i + 4` instead
of `boot_addr_i`.

This is tracked upstream as:

```text
https://github.com/openhwgroup/cv32e40x/issues/993
```

Project status: CV32E40X is currently excluded from CoreJack's supported
regression set. Keep it treated as experimental until the upstream behavior is
clarified or fixed.

With:

```text
boot_addr_i = 0x80000080
```

the first accepted external instruction request observed at the CV32E40X
boundary is:

```text
instr_req_o && instr_gnt_i
instr_addr_o = 0x80000084
```

However, the core IF stage tracks the corresponding instruction as:

```text
pc_if_o = 0x80000080
```

This suggests that the core requests instruction memory word `0x80000084`, but
then treats the returned instruction data as belonging to PC `0x80000080`.

## Expected Behavior

For an instruction request accepted by:

```text
instr_req_o && instr_gnt_i
```

the accepted `instr_addr_o` value should identify the instruction memory word
whose data will later be returned on `instr_rdata_i`.

Therefore, after reset with:

```text
boot_addr_i = 0x80000080
```

the first accepted instruction fetch is expected to request:

```text
instr_addr_o = 0x80000080
```

## Observed Behavior

An opt-in simulation checker records every accepted raw CV32E40X instruction
request and compares it with the IF-stage PC for the consumed instruction word.

The first observed transaction is:

```text
cv32e40x-if accept cycle=5 raw_addr=0x80000084 adapted_addr=0x80000080
cv32e40x-if consume cycle=8 pc_if=0x80000080 pc_word=0x80000080 raw_requested=no

CV32E40X IF contract mismatch:
consumed instruction PC 0x80000080, but the raw core boundary never accepted
an instruction fetch for word address 0x80000080.
Accepted raw fetch words: 0x80000084
```

The `adapted_addr` field is a local SoC wrapper workaround and is not part of
the raw CV32E40X interface. It subtracts 4 from `instr_addr_o` so that the SoC
memory receives the address expected by the IF-stage PC tracking. With that
workaround disabled, the software image does not execute correctly.

## Suspected RTL Area

The suspicious logic is in `cv32e40x_prefetcher.sv`:

```systemverilog
assign trans_addr_incr = {trans_addr_q[31:1], 1'b0} + 32'd4;

if (fetch_branch_i) begin
  trans_addr_o = fetch_branch_addr_i;
end else begin
  trans_addr_o = trans_addr_incr;
end

...

if (fetch_branch_i || (trans_valid_o && trans_ready_i)) begin
  trans_addr_q <= trans_addr_o;
end
```

This appears to update `trans_addr_q` on a boot/branch redirect even when no
instruction request was accepted in that cycle. If the redirect address is
stored without an accepted request, the next accepted request can become
`fetch_branch_addr_i + 4`.

## Reproduction Context

The failing observation was reproduced with current upstream `HEAD`:

```text
CV32E40X revision: d952cd63bc1b4eb58cd893c28ef8283c781e345e
RV32I configuration
M extension enabled
CLIC disabled
fetch_enable_i tied high
Verilator simulation
```

The same behavior was originally observed on the `0.10.0` tag:

```text
CV32E40X 0.10.0 revision: 18c88fd78a37f270c8301c552f5fd0f564d0ab20
```

The instruction memory side accepts requests using:

```text
instr_req_o && instr_gnt_i
```

## Questions

1. Is `instr_addr_o` intended to be the address of the instruction memory word
   being requested?
2. If yes, should `trans_addr_q` only advance from a boot/branch target after
   the request for that target has been accepted?
3. Is there an existing configuration requirement or integration constraint that
   would explain why the first accepted instruction request is `boot_addr_i + 4`?
