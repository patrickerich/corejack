// SPDX-License-Identifier: Apache-2.0
//
// CoreJack-owned CVA6 configuration. The package name cva6_config_pkg is
// mandated by CVA6; the cva6_ file prefix avoids a collision with other
// cores' config packages (style exception: filename != package name).
package cva6_config_pkg;
  localparam int unsigned CVA6ConfigXlen = 64;
  localparam bit CVA6ConfigRvfiTrace = 1'b0;
  localparam int unsigned CVA6ConfigAxiIdWidth = 4;
  localparam int unsigned CVA6ConfigAxiAddrWidth = 48;
  localparam int unsigned CVA6ConfigAxiDataWidth = 64;
  localparam int unsigned CVA6ConfigAxiUserWidth = 1;

  localparam config_pkg::cva6_user_cfg_t cva6_cfg = '{
    XLEN: unsigned'(CVA6ConfigXlen),
    VLEN: unsigned'(64),
    FpgaEn: bit'(0),
    FpgaAlteraEn: bit'(0),
    TechnoCut: bit'(0),
    SuperscalarEn: bit'(0),
    ALUBypass: bit'(0),
    NrCommitPorts: unsigned'(1),
    AxiAddrWidth: unsigned'(CVA6ConfigAxiAddrWidth),
    AxiDataWidth: unsigned'(CVA6ConfigAxiDataWidth),
    AxiIdWidth: unsigned'(CVA6ConfigAxiIdWidth),
    AxiUserWidth: unsigned'(CVA6ConfigAxiUserWidth),
    MemTidWidth: unsigned'(2),
    NrLoadBufEntries: unsigned'(2),
    RVF: bit'(0),
    RVD: bit'(0),
    XF16: bit'(0),
    XF16ALT: bit'(0),
    XF8: bit'(0),
    RVA: bit'(0),
    RVB: bit'(0),
    ZKN: bit'(0),
    RVV: bit'(0),
    RVC: bit'(1),
    RVH: bit'(0),
    RVZCMT: bit'(0),
    RVZCB: bit'(0),
    RVZCMP: bit'(0),
    XFVec: bit'(0),
    CvxifEn: bit'(0),
    CoproType: config_pkg::COPRO_NONE,
    RVZiCond: bit'(0),
    RVZiCbom: bit'(0),
    RVZicntr: bit'(0),
    RVZihpm: bit'(0),
    NrScoreboardEntries: unsigned'(8),
    PerfCounterEn: bit'(0),
    MmuPresent: bit'(0),
    RVS: bit'(0),
    RVU: bit'(0),
    // Gate for mip.MSIP: must be enabled for the CLINT software interrupt
    // wired to ipi_i (the platform IPI contract every supported core honors).
    SoftwareInterruptEn: bit'(1),
    HaltAddress: 64'h800,
    ExceptionAddress: 64'h810,
    RASDepth: unsigned'(2),
    BTBEntries: unsigned'(0),
    BPType: config_pkg::BHT,
    BHTEntries: unsigned'(0),
    BHTHist: unsigned'(3),
    DmBaseAddress: 64'h0,
    TvalEn: bit'(0),
    // Vectored mtvec support is required by the platform interrupt contract:
    // bare-metal apps point mtvec at the crt0 vector table in vectored mode
    // (the portable choice across Ibex/CV32E40*, which are vectored-only).
    // Direct mode still works when software writes mtvec[0] = 0.
    DirectVecOnly: bit'(0),
    NrPMPEntries: unsigned'(0),
    PMPCfgRstVal: {64{64'h0}},
    PMPAddrRstVal: {64{64'h0}},
    PMPEntryReadOnly: 64'd0,
    PMPNapotEn: bit'(0),
    NOCType: config_pkg::NOC_TYPE_AXI4_ATOP,
    NrNonIdempotentRules: unsigned'(0),
    NonIdempotentAddrBase: 1024'({64'b0, 64'b0}),
    NonIdempotentLength: 1024'({64'b0, 64'b0}),
    NrExecuteRegionRules: unsigned'(2),
    ExecuteRegionAddrBase: 1024'({64'h0, 64'h8000_0000}),
    ExecuteRegionLength: 1024'({64'h1000, 64'h4000_0000}),
    NrCachedRegionRules: unsigned'(0),
    CachedRegionAddrBase: 1024'({64'h8000_0000}),
    CachedRegionLength: 1024'({64'h4000_0000}),
    MaxOutstandingStores: unsigned'(4),
    DebugEn: bit'(1),
    SDTRIG: bit'(0),
    Mcontrol6: bit'(0),
    Icount: bit'(0),
    Etrigger: bit'(0),
    Itrigger: bit'(0),
    AxiBurstWriteEn: bit'(0),
    IcacheByteSize: unsigned'(2048),
    IcacheSetAssoc: unsigned'(2),
    IcacheLineWidth: unsigned'(64),
    DCacheType: config_pkg::WT,
    DcacheByteSize: unsigned'(2048),
    DcacheSetAssoc: unsigned'(2),
    DcacheLineWidth: unsigned'(128),
    DcacheFlushOnFence: bit'(0),
    DcacheFlushOnFenceI: bit'(0),
    DcacheInvalidateOnFlush: bit'(0),
    DataUserEn: unsigned'(0),
    WtDcacheWbufDepth: int'(4),
    FetchUserWidth: unsigned'(1),
    FetchUserEn: unsigned'(0),
    InstrTlbEntries: int'(2),
    DataTlbEntries: int'(2),
    UseSharedTlb: bit'(0),
    SvnapotEn: bit'(0),
    SharedTlbDepth: int'(2),
    NrLoadPipeRegs: int'(0),
    NrStorePipeRegs: int'(0),
    DcacheIdWidth: int'(1)
  };
endpackage
