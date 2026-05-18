# Third-Party Notices

CoreJack-authored code is licensed under the Apache License, Version 2.0,
unless a file explicitly says otherwise.

This repository also uses third-party code and hardware IP. Third-party files
remain under their original licenses and are not relicensed by the CoreJack
license.

## Vendored Code

### Ibex

Files under `rtl/cores/vendored/corejack_ibex/` are derived from Ibex and
OpenTitan/lowRISC source files. These files carry Apache-2.0 SPDX headers and
copyright notices from their original authors.

### Tiny printf

Files under `sw/c/common/printf.*` are based on the MIT-licensed tiny printf
implementation by Marco Paland. The local files retain this attribution in
their file headers.

## Bender-Managed Dependencies

RTL dependencies listed in `Bender.yml` are fetched into local, gitignored
checkout directories by the dependency flow. Their license files and SPDX
headers are provided by the corresponding upstream projects.

Current Bender-managed dependency families include:

- `pulp-platform/axi`
- `pulp-platform/riscv-dbg`
- `pulp-platform/apb`
- `pulp-platform/apb_uart`
- `pulp-platform/obi`
- `openhwgroup/cv32e40p` (optional checkout via Bender `vendor_package`)
- `olofk/serv` (optional checkout via Bender `vendor_package`)

These dependencies include permissive hardware/software licenses such as
Apache-2.0 and Solderpad Hardware License variants. Consult each fetched
dependency checkout for the exact license terms that apply to that package.
