using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Combat;
using MegaCrit.Sts2.Core.Context;
using MegaCrit.Sts2.Core.Modding;
using MegaCrit.Sts2.Core.Helpers;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes.Combat;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;
using MegaCrit.Sts2.Core.Rooms;
using MegaCrit.Sts2.Core.Saves;

namespace Hcxmmx.SothebySkin;

[ModInitializer(nameof(Init))]
public static class Entry
{
    private static bool _initialized;
    public static void Init()
    {
        if (_initialized) return;
        _initialized = true;
        new Harmony("hcxmmx.sotheby.visuals").PatchAll(typeof(Entry).Assembly);
        HextechAudioCompat.Initialize();
        CombatManager.Instance.CombatWon += OnCombatWon;
        if (Engine.GetMainLoop() is SceneTree tree)
        {
#if SELECT_DIAGNOSTIC
            SelectDiagnostic.Start(tree);
#endif
            var warmupScript = ResourceLoader.Load<GDScript>("res://Sotheby_Hcxmmx/UltimateWarmup.gd");
            if (warmupScript?.New().AsGodotObject() is Node warmup)
            {
                warmup.Name = "SothebyUltimateWarmup";
                tree.Root.CallDeferred(Node.MethodName.AddChild, warmup);
            }
            var coverWarmupScript = ResourceLoader.Load<GDScript>("res://Sotheby_Hcxmmx/CoverWarmup.gd");
            if (coverWarmupScript?.New().AsGodotObject() is Node coverWarmup)
            {
                coverWarmup.Name = "SothebyCoverWarmup";
                tree.Root.CallDeferred(Node.MethodName.AddChild, coverWarmup);
            }
            var timer = new Godot.Timer { Name = "SothebyAudioPolicy", WaitTime = 0.5, Autostart = true, ProcessMode = Node.ProcessModeEnum.Always };
            timer.Timeout += Visuals.UpdateSoundPolicy;
            tree.Root.CallDeferred(Node.MethodName.AddChild, timer);
        }
        GD.Print("[SothebySkin] Initialized. Visual/audio hooks only; target=SILENT.");
    }

    private static void OnCombatWon(CombatRoom room)
    {
        foreach (var id in Visuals.Active.ToArray())
        {
            if (GodotObject.InstanceFromId(id) is Node2D node && GodotObject.IsInstanceValid(node))
                node.Call("request_victory");
            else Visuals.Active.Remove(id);
        }
    }
}

internal static class Visuals
{
    internal const string NodeName = "SothebySkin";
    internal static readonly HashSet<ulong> Active = new();
    private static readonly HashSet<ulong> SoundNodes = new();
    private static PackedScene? _portrait;
    private static PackedScene? _battle;
#if SELECT_DIAGNOSTIC
    private static readonly Dictionary<ulong, int> SelectTickets = new();
#endif
    internal static bool IsTarget(CharacterModel? model) => string.Equals(model?.Id.Entry, "SILENT", StringComparison.OrdinalIgnoreCase);

    internal static void Select(NCharacterSelectScreen screen, CharacterModel model)
    {
        if (!IsTarget(model)) return;
#if SELECT_DIAGNOSTIC
        if (SelectDiagnostic.ProbeDeferred)
        {
        var id = screen.GetInstanceId();
        int ticket = SelectTickets.GetValueOrDefault(id);
        GD.Print("[SothebySkin] Cover requested for " + model.Id.Entry + "; deferring attachment.");
        Callable.From(() =>
        {
            GD.Print("[SothebySelectDiagnostic] Deferred callback: valid=" + GodotObject.IsInstanceValid(screen) +
                ", inside=" + screen.IsInsideTree() + ", ticket=" + ticket + "/" + SelectTickets.GetValueOrDefault(id));
            if (GodotObject.IsInstanceValid(screen) && screen.IsInsideTree() &&
                SelectTickets.GetValueOrDefault(id) == ticket) AttachCover(screen, model);
        }).CallDeferred();
            return;
        }
#endif
        GD.Print("[SothebySkin] Cover selected: " + model.Id.Entry + "; attaching through native background reference.");
        AttachCover(screen, model);
    }

    internal static Control SelectHost(NCharacterSelectScreen screen)
    {
        // Follow the working Flandre skin: use the native cached container
        // reference and keep the game's existing selection controls intact.
        var bg = Traverse.Create(screen).Field("_bgContainer").GetValue<Control>();
        return bg?.GetParent<Control>() ?? screen;
    }

    private static void AttachCover(NCharacterSelectScreen screen, CharacterModel model)
    {
        try
        {
            var host = SelectHost(screen);
            var container = Traverse.Create(screen).Field("_bgContainer").GetValue<Control>() ?? host.GetNodeOrNull<Control>("AnimatedBg");
            if (container == null) throw new InvalidOperationException("AnimatedBg is missing from the current select screen.");
            GD.Print("[SothebySkin] Cover host: sourceInside=" + screen.IsInsideTree() +
                ", hostInside=" + host.IsInsideTree() + ", background=" + container.Name);
            var node = host.GetNodeOrNull<Control>(NodeName);
            _portrait ??= ResourceLoader.Load<PackedScene>("res://Sotheby_Hcxmmx/Portrait.tscn");
            if (_portrait == null) throw new InvalidOperationException("Portrait scene could not load.");
            if (node == null)
            {
                var warmer = screen.GetTree().GetFirstNodeInGroup("sotheby_cover_cache");
                node = warmer?.Call("acquire").AsGodotObject() as Control;
                node ??= _portrait.Instantiate<Control>();
                node.Name = NodeName;
                if (node.GetParent() != null) node.Reparent(host, false);
                else host.AddChild(node);
                node.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
                // Draw over both native backgrounds, below all native controls.
                host.MoveChild(node, container!.GetIndex() + 1);
                RegisterSoundNode(node);
                WireCoverControls(screen, host, node);
            }
            if (!node.Call("is_ready").AsBool())
            {
                GD.PushWarning("[SothebySkin] Portrait did not initialize on the live host.");
                node.QueueFree();
                return;
            }
            var relic = model.StartingRelics.FirstOrDefault();
            var cards = new Godot.Collections.Array<string>();
            foreach (var group in model.StartingDeck.GroupBy(card => card.Id.Entry))
                cards.Add(group.First().Title + "  × " + group.Count());
            node.Call("configure", host, new Godot.Collections.Dictionary
            {
                ["hp"] = $"{model.StartingHp}/{model.StartingHp}", ["gold"] = model.StartingGold.ToString(),
                ["relic_title"] = relic?.Title.GetFormattedText() ?? "",
                ["relic_description"] = PlainText(relic?.DynamicDescription.GetFormattedText() ?? ""),
                ["relic_icon"] = relic is null ? default(Variant) : relic.Icon, ["cards"] = cards,
                ["ascension"] = Traverse.Create(screen).Field("_ascensionPanel").GetValue<NAscensionPanel>().Ascension,
                ["ascension_state"] = ReadAscension(screen)
            });
            UpdateSoundPolicy();
            GD.Print("[SothebySkin] Archive cover and bilingual subtitles attached. selfVisible=" + node.Visible +
                ", treeVisible=" + node.IsVisibleInTree() + ", active=" + node.Get("active").AsBool());
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Character select: " + ex); }
    }

    private static string PlainText(string value) => System.Text.RegularExpressions.Regex.Replace(value, @"\[[^\]]+\]", "");

    private static Godot.Collections.Dictionary ReadAscension(NCharacterSelectScreen screen)
    {
        var panel = Traverse.Create(screen).Field("_ascensionPanel").GetValue<NAscensionPanel>();
        int max = (int)(AccessTools.Field(typeof(NAscensionPanel), "_maxAscension").GetValue(panel) ?? 0);
        bool editable = (bool)(AccessTools.Field(typeof(NAscensionPanel), "_arrowsVisible").GetValue(panel) ?? false);
        return new Godot.Collections.Dictionary
        {
            ["level"] = panel.Ascension, ["max_level"] = max, ["editable"] = editable,
            ["title"] = PlainText(AscensionHelper.GetTitle(panel.Ascension).GetFormattedText()),
            ["description"] = PlainText(AscensionHelper.GetDescription(panel.Ascension).GetFormattedText())
        };
    }

    private static void WireCoverControls(NCharacterSelectScreen screen, Control host, Control cover)
    {
        var panel = Traverse.Create(screen).Field("_ascensionPanel").GetValue<NAscensionPanel>();
        void Refresh()
        {
            if (GodotObject.IsInstanceValid(cover) && !cover.IsQueuedForDeletion())
                cover.Call("update_ascension", ReadAscension(screen));
        }
        cover.Connect("ascension_requested", Callable.From<int>(direction =>
        {
            if (!cover.Visible || direction == 0) return;
            var state = ReadAscension(screen);
            if (!state["editable"].AsBool()) return;
            // Reuse the exact vanilla +/- handlers; native signals update the
            // lobby, preferences and multiplayer synchronization as before.
            AccessTools.Method(typeof(NAscensionPanel), direction < 0 ? "DecrementAscension" : "IncrementAscension").Invoke(panel, null);
            Refresh();
        }));
        cover.Connect("open_settings_requested", Callable.From(() => SkinSettings.Open(host)));
        var refresh = Callable.From(Refresh);
        panel.Connect(NAscensionPanel.SignalName.AscensionLevelChanged, refresh);
        cover.TreeExiting += () =>
        {
            if (GodotObject.IsInstanceValid(panel) && panel.IsConnected(NAscensionPanel.SignalName.AscensionLevelChanged, refresh))
                panel.Disconnect(NAscensionPanel.SignalName.AscensionLevelChanged, refresh);
        };
#if SELECT_DIAGNOSTIC
        host.TreeExiting += () => SelectTickets.Remove(screen.GetInstanceId());
#endif
    }

    internal static void CloseSelect(NCharacterSelectScreen screen, string reason = "selection")
    {
#if SELECT_DIAGNOSTIC
        var id = screen.GetInstanceId();
        SelectTickets[id] = SelectTickets.GetValueOrDefault(id) + 1;
#endif
        var node = SelectHost(screen).GetNodeOrNull<Control>(NodeName);
        if (node != null) GD.Print("[SothebySkin] Cover close: " + reason + ", selfVisible=" + node.Visible);
        node?.Call("prepare_selection");
    }

    internal static void Attach(NCreature creature)
    {
        if (!IsTarget(creature.Entity?.Player?.Character)) return;
        var visuals = creature.Visuals;
        if (visuals == null || visuals.GetNodeOrNull(NodeName) != null) return;
        try
        {
            var attachClock = System.Diagnostics.Stopwatch.StartNew();
            _battle ??= ResourceLoader.Load<PackedScene>("res://Sotheby_Hcxmmx/Battle.tscn");
            if (_battle == null) throw new InvalidOperationException("Battle scene could not load.");
            var original = visuals.GetNodeOrNull<Node2D>("%Visuals");
            if (original == null) return;
            var node = _battle.Instantiate<Node2D>();
            node.Name = NodeName;
            visuals.AddChild(node);
            if (!node.Call("is_ready").AsBool()) { node.QueueFree(); return; }
            RegisterSoundNode(node);
            UpdateSoundPolicy();
            if (!node.Call("configure", original, visuals.Bounds.Position, visuals.Bounds.Size, LocalContext.IsMe(creature.Entity)).AsBool())
            {
                node.QueueFree();
                return;
            }
            // Battle.gd owns visibility suppression/restoration. The hidden original
            // still supplies animation timing and attachment points.
            original.Hide();
            var id = node.GetInstanceId();
            Active.Add(id);
            node.TreeExiting += () =>
            {
                Active.Remove(id);
            };
            GD.Print("[SothebySkin] Combat attached in " + attachClock.Elapsed.TotalMilliseconds.ToString("F1", System.Globalization.CultureInfo.InvariantCulture) + "ms; local voice=" + LocalContext.IsMe(creature.Entity));
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Combat attach: " + ex); }
    }

    internal static void Trigger(NCreature creature, string trigger)
    {
        if (!IsTarget(creature.Entity?.Player?.Character)) return;
        var node = creature.Visuals?.GetNodeOrNull<Node2D>(NodeName);
        if (node != null)
        {
            // The native death/hurt path can reset alpha. Suppress rendering again
            // after that trigger without disabling its animator or gameplay waits.
            creature.Visuals?.Body.Hide();
            node.Call("handle_trigger", trigger);
        }
    }

    internal static void UpdateSoundPolicy()
    {
        try
        {
            var save = SaveManager.Instance;
            float gain = Math.Clamp(save.SettingsSave.VolumeMaster * save.SettingsSave.VolumeSfx * 0.8f, 0f, 1f);
            foreach (var id in SoundNodes.ToArray())
            {
                if (GodotObject.InstanceFromId(id) is Node node && GodotObject.IsInstanceValid(node))
                    node.Call("set_audio_policy", gain, save.PrefsSave.MuteInBackground);
                else SoundNodes.Remove(id);
            }
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Audio policy: " + ex.Message); }
    }

    private static void RegisterSoundNode(Node node)
    {
        var id = node.GetInstanceId();
        SoundNodes.Add(id);
        node.TreeExiting += () => SoundNodes.Remove(id);
    }
}

[HarmonyPatch(typeof(NCharacterSelectScreen), nameof(NCharacterSelectScreen.SelectCharacter))]
internal static class CharacterSelectPatch
{
    private static void Prefix(NCharacterSelectScreen __instance) => Visuals.CloseSelect(__instance, "character changing");
    private static void Postfix(NCharacterSelectScreen __instance, NCharacterSelectButton charSelectButton, CharacterModel characterModel)
    {
        if (!charSelectButton.IsLocked && !charSelectButton.IsRandom) Visuals.Select(__instance, characterModel);
    }
}

[HarmonyPatch(typeof(NCharacterSelectScreen), nameof(NCharacterSelectScreen.OnSubmenuClosed))]
internal static class CharacterSelectClosedPatch
{
    private static void Prefix(NCharacterSelectScreen __instance) => Visuals.CloseSelect(__instance, "submenu closed");
}

[HarmonyPatch(typeof(NCreature), nameof(NCreature._Ready))]
internal static class CreatureReadyPatch
{
    private static void Postfix(NCreature __instance) => Visuals.Attach(__instance);
}

[HarmonyPatch(typeof(NCreature), nameof(NCreature.SetAnimationTrigger))]
internal static class AnimationPatch
{
    private static void Postfix(NCreature __instance, string trigger) => Visuals.Trigger(__instance, trigger);
}
