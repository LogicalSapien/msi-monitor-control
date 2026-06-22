using MsiMonitorControl;
using Xunit;

namespace MsiMonitorControl.Tests;

/// <summary>
/// Unit tests for the PBP edge-switch KVM feature (v0.2.3, design §W6).
/// Tests the pure logic in <see cref="EdgeSwitchLogic"/> and the static
/// <see cref="EdgeSwitchTracker.KvmCommandForInput"/> mapping — no message pump,
/// no Win32 hook, no real display needed. Runs cleanly in CI on windows-latest.
/// </summary>
public class EdgeSwitchTests
{
    // Local alias so the test bodies can use the short name; mirrors the public
    // constant on EdgeSwitchTracker (the dwell-suppression window in ms).
    private const int DwellMs = EdgeSwitchTracker.DwellMs;

    // =========================================================================
    // Input → KVM mapping (§4.2)
    // =========================================================================

    [Fact]
    public void KvmCommandForInput_TypeC_ReturnsKvmUsbC()
    {
        Assert.Equal(CommandKind.KvmUsbC, EdgeSwitchTracker.KvmCommandForInput(Command.PbpInput.TypeC));
    }

    [Fact]
    public void KvmCommandForInput_Dp_ReturnsKvmUpstream()
    {
        Assert.Equal(CommandKind.KvmUpstream, EdgeSwitchTracker.KvmCommandForInput(Command.PbpInput.Dp));
    }

    [Fact]
    public void KvmCommandForInput_Hdmi1_ReturnsNull()
    {
        // HDMI — ambiguous KVM port mapping → no auto-switch (§4.1).
        Assert.Null(EdgeSwitchTracker.KvmCommandForInput(Command.PbpInput.Hdmi1));
    }

    [Fact]
    public void KvmCommandForInput_Hdmi2_ReturnsNull()
    {
        Assert.Null(EdgeSwitchTracker.KvmCommandForInput(Command.PbpInput.Hdmi2));
    }

    // =========================================================================
    // Hysteresis constants (§5)
    // =========================================================================

    [Fact]
    public void DeadZonePixels_Is48()
    {
        // The design spec pins this at 48 px (§5.1). This test guards against accidental drift.
        Assert.Equal(48, EdgeSwitchTracker.DeadZonePixels);
    }

    [Fact]
    public void DwellMs_Is800()
    {
        // The design spec pins this at 800 ms (§5.2).
        Assert.Equal(800, EdgeSwitchTracker.DwellMs);
    }

    // =========================================================================
    // EdgeSwitchLogic — divider logic via a fake clock
    // =========================================================================
    //
    // The divider is at x=1720 (centre of 3440 px, origin=0).
    // Dead zone: [1720-48, 1720+48] = [1672, 1768]. Anything outside triggers.

    private const int DividerX = 1720;

    // Builds a logic instance with a fake clock (returns fake tick count in ms).
    private static (EdgeSwitchLogic logic, Func<long, long> advance) MakeLogic()
    {
        long fakeTick = 0;
        var logic = new EdgeSwitchLogic();
        logic.SetTickSource(() => fakeTick);
        return (logic, ms => fakeTick += ms);
    }

    private static CommandKind? Move(EdgeSwitchLogic logic, int x,
        Command.PbpInput main = Command.PbpInput.TypeC,
        Command.PbpInput sub  = Command.PbpInput.Dp) =>
        logic.Evaluate(x, DividerX, main, sub);

    // -------------------------------------------------------------------------
    // First move: just establishes the side, no switch
    // -------------------------------------------------------------------------

    [Fact]
    public void FirstMove_EstablishesSideWithoutSwitch()
    {
        var (logic, _) = MakeLogic();
        // First call — side transitions Unknown→Left; no switch yet.
        var result = Move(logic, 100);
        Assert.Null(result);
    }

    // -------------------------------------------------------------------------
    // Basic crossing
    // -------------------------------------------------------------------------

    [Fact]
    public void CrossToRight_SendsMainSourceKvm()
    {
        // mainSource=TypeC → KvmUsbC when cursor enters the right half.
        var (logic, advance) = MakeLogic();
        Move(logic, 100);                     // establish Left
        advance(DwellMs + 1);                 // past dwell
        var result = Move(logic, 1800);       // cross to Right
        Assert.Equal(CommandKind.KvmUsbC, result);
    }

    [Fact]
    public void CrossToLeft_SendsSubSourceKvm()
    {
        // subSource=Dp → KvmUpstream when cursor enters the left half.
        var (logic, advance) = MakeLogic();
        Move(logic, 1800);                    // establish Right
        advance(DwellMs + 1);
        var result = Move(logic, 100);        // cross to Left
        Assert.Equal(CommandKind.KvmUpstream, result);
    }

    // -------------------------------------------------------------------------
    // Dead zone (§5.1)
    // -------------------------------------------------------------------------

    [Fact]
    public void InsideDeadZone_NoSwitch()
    {
        var (logic, advance) = MakeLogic();
        Move(logic, 100);       // establish Left
        advance(DwellMs + 1);

        // Cursor enters dead zone but does not exit on the far side.
        Assert.Null(Move(logic, 1720));   // exactly at divider
        Assert.Null(Move(logic, 1750));   // inside dead zone on right side (< 1720+48=1768)
        Assert.Null(Move(logic, 1710));   // back inside dead zone on left side
    }

    [Fact]
    public void ExitsDeadZoneOnFarSide_Switches()
    {
        var (logic, advance) = MakeLogic();
        Move(logic, 100);              // establish Left
        advance(DwellMs + 1);

        Move(logic, 1750);             // inside dead zone — no switch
        Assert.Null(Move(logic, 1768)); // still inside (1720+48=1768 is the last inside pixel)
        var result = Move(logic, 1769); // one pixel past dead zone → switch
        Assert.Equal(CommandKind.KvmUsbC, result);
    }

    [Fact]
    public void RetreatsFromDeadZone_NoSwitch()
    {
        // Cursor enters dead zone from the left, then returns to the left — no switch.
        var (logic, advance) = MakeLogic();
        Move(logic, 100);        // establish Left
        advance(DwellMs + 1);
        Move(logic, 1750);       // enter dead zone
        var result = Move(logic, 100); // retreat to Left without exiting on the right
        Assert.Null(result);
    }

    // -------------------------------------------------------------------------
    // Dwell suppression (§5.2)
    // -------------------------------------------------------------------------

    [Fact]
    public void SecondCrossingWithinDwell_Suppressed()
    {
        var (logic, advance) = MakeLogic();
        Move(logic, 100);
        advance(DwellMs + 1);
        var first = Move(logic, 1800);   // → KvmUsbC
        Assert.Equal(CommandKind.KvmUsbC, first);

        // Immediately cross back — within DwellMs → suppressed.
        var second = Move(logic, 100);
        Assert.Null(second);
    }

    [Fact]
    public void SecondCrossingAfterDwell_Fires()
    {
        var (logic, advance) = MakeLogic();
        Move(logic, 100);
        advance(DwellMs + 1);
        Move(logic, 1800);               // first crossing

        advance(DwellMs + 1);            // wait past dwell
        var result = Move(logic, 100);   // second crossing
        Assert.Equal(CommandKind.KvmUpstream, result);
    }

    [Fact]
    public void CrossingJustBeforeDwellExpiry_Suppressed()
    {
        // A crossing at DwellMs - 1 ms is still suppressed.
        var (logic, advance) = MakeLogic();
        Move(logic, 100);
        advance(DwellMs + 1);
        Move(logic, 1800);

        advance(DwellMs - 1);             // one ms before dwell expires
        var result = Move(logic, 100);
        Assert.Null(result);
    }

    // -------------------------------------------------------------------------
    // HDMI source → no switch
    // -------------------------------------------------------------------------

    [Fact]
    public void HdmiMainSource_NoKvmSent()
    {
        var (logic, advance) = MakeLogic();
        Move(logic, 100, sub: Command.PbpInput.Dp, main: Command.PbpInput.Hdmi1);
        advance(DwellMs + 1);
        var result = logic.Evaluate(1800, DividerX, Command.PbpInput.Hdmi1, Command.PbpInput.Dp);
        Assert.Null(result); // HDMI main → no switch
    }

    [Fact]
    public void HdmiSubSource_NoKvmSent()
    {
        var (logic, advance) = MakeLogic();
        Move(logic, 1800, main: Command.PbpInput.TypeC, sub: Command.PbpInput.Hdmi2);
        advance(DwellMs + 1);
        var result = logic.Evaluate(100, DividerX, Command.PbpInput.TypeC, Command.PbpInput.Hdmi2);
        Assert.Null(result); // HDMI sub → no switch
    }

    // -------------------------------------------------------------------------
    // Reset (called on PBP activation)
    // -------------------------------------------------------------------------

    [Fact]
    public void Reset_ClearsSideState()
    {
        // After Reset, the first move in any direction just establishes the side (no switch).
        var (logic, advance) = MakeLogic();
        Move(logic, 100);           // establish Left
        advance(DwellMs + 1);
        logic.Reset();              // simulate PBP going on again

        // First move after reset should not fire a switch.
        var result = Move(logic, 1800);
        Assert.Null(result);
    }
}
