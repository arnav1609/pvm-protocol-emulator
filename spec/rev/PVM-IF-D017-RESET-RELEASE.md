# D-017 reset release

Approved in chat on 21 November 2026 for the pre-freeze optimization
branch. The external reset pin is still active low.

PVM asserts the internal reset asynchronously when `rst_n` falls. The
internal reset stays asserted across the first two rising edges after
`rst_n` returns high and deasserts just after the second edge.
Existing synchronous reset consumers sample it low through that edge
and resume ordinary operation on the third edge.

Reset during RUN reaches those consumers on the next rising clock edge.
The lifecycle state goes to HALT and the registered pin outputs take
their reset values. Host software must allow the clock to run through
reset release before starting SPI.

The D017 jobs cover asynchronous assertion, the two-edge release, and
propagation of a reset pulse between clock edges. The early-release
mutant must fail the release check. The existing frozen bench counts
and D-016 golden vectors are retained.
[Reset bench](../../tb_rtl/tb_reset_sync.v) · [Candidate gate](../../results/opt_area_timing.md)

## ASIC RTL attribute addendum

Approved in chat on 21 November 2026. Remove the FPGA-specific
`ASYNC_REG` annotation from `pvm_top.v`. The two reset stages still
assert asynchronously and release on the same two core-clock edges.
An FPGA-specific flow can attach the equivalent placement constraint
in its XDC. [Reset RTL](../../src/pvm_top.v)
