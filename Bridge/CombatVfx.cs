using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Commands.Builders;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes.Combat;
using MegaCrit.Sts2.Core.Nodes.Vfx;
using MegaCrit.Sts2.Core.Saves;
using MegaCrit.Sts2.Core.Settings;
using MegaCrit.Sts2.Core.ValueProps;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace Hcxmmx.SothebySkin;

// Observe the concrete target-selection and damage-dispatch calls. No task is
// replaced, awaited, or delayed; no argument/result or combat RNG is changed.
internal static class CombatVfx
{
    private sealed record Pending(long Ticket, AttackCommand Command);
    private static readonly ConditionalWeakTable<Creature, Pending> Plans = new();
    private static long _ticket;
    private static readonly FieldInfo AnimDelay = AccessTools.Field(typeof(AttackCommand), "_attackerAnimDelay");
    private static readonly FieldInfo ExtraWait = AccessTools.Field(typeof(AttackCommand), "_waitBeforeHit");

    private static Node2D? Skin(Creature? creature) => creature != null && Visuals.IsTarget(creature.Player?.Character)
        ? creature.GetCreatureNode()?.Visuals?.GetNodeOrNull<Node2D>(Visuals.NodeName) : null;

    private static Godot.Collections.Dictionary? Snapshot(Creature target)
    {
        var node = target.GetCreatureNode();
        if (node == null || !GodotObject.IsInstanceValid(node)) return null;
        return new Godot.Collections.Dictionary
        {
            ["id"] = (long)node.GetInstanceId(), ["node"] = node,
            ["ground"] = node.GetBottomOfHitbox(),
            ["center"] = node.Visuals?.VfxSpawnPosition?.GlobalPosition ?? node.GetBottomOfHitbox() - new Vector2(0, 80)
        };
    }

    internal static void Plan(AttackCommand command, IReadOnlyList<Creature> targets)
    {
        try
        {
            var dealer = command.Attacker;
            var skin = Skin(dealer);
            if (skin == null || dealer == null || dealer.IsDead) return;
            long ticket = ++_ticket;
            Plans.Remove(dealer); Plans.Add(dealer, new Pending(ticket, command));
            var snapshots = new Godot.Collections.Array<Godot.Collections.Dictionary>();
            // Random attacks throw bottles toward all eligible live candidates;
            // only the real damage target gets a circle and impact. Do not sample RNG.
            for (int i = 0; i < targets.Count; i++)
                if (targets[i].IsAlive && Snapshot(targets[i]) is { } snapshot) snapshots.Add(snapshot);
            float delay = (float)(AnimDelay.GetValue(command) ?? 0.2f);
            var extra = (float[]?)ExtraWait.GetValue(command);
            var fast = SaveManager.Instance.PrefsSave.FastMode;
            float wait = fast == FastModeType.Instant ? 0 : fast == FastModeType.Fast ? Mathf.Min(delay * .5f, .25f) : delay;
            if (extra is { Length: >= 2 } && fast != FastModeType.Instant) wait += Mathf.Max(0, extra[fast == FastModeType.Fast ? 0 : 1]);
            skin.Call("plan_attack", ticket, snapshots, wait, fast != FastModeType.Normal, command.IsRandomlyTargeted);
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] VFX plan: " + ex.Message); }
    }

    internal static void Hit(Creature? dealer, IEnumerable<Creature>? targets, ValueProp props, CardModel? card)
    {
        try
        {
            if (dealer == null || dealer.IsDead || !props.HasFlag(ValueProp.Move) ||
                !Plans.TryGetValue(dealer, out var plan) || !ReferenceEquals(plan.Command.ModelSource, card)) return;
            var skin = Skin(dealer);
            if (skin == null) return;
            // AttackCommand's actual damage call supplies a materialized List.
            // Avoid enumerating any unknown lazy collection a second time.
            if (targets is not IReadOnlyList<Creature> actual) return;
            for (int i = 0; i < actual.Count; i++)
                if (actual[i].IsAlive && Snapshot(actual[i]) is { } snapshot)
                    skin.Call("confirm_hit", plan.Ticket, snapshot);
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] VFX impact: " + ex.Message); }
    }
}

[HarmonyPatch(typeof(AttackCommand), "GetPossibleTargets")]
internal static class AttackTargetsPatch
{
    private static void Postfix(AttackCommand __instance, IReadOnlyList<Creature> __result) => CombatVfx.Plan(__instance, __result);
}

[HarmonyPatch]
internal static class AttackDamagePatch
{
    private static MethodBase TargetMethod() => typeof(CreatureCmd).GetMethods().Single(method =>
        method.Name == nameof(CreatureCmd.Damage) && method.GetParameters() is var args && args.Length is 6 or 7 &&
        args[1].ParameterType == typeof(IEnumerable<Creature>) && args[2].ParameterType == typeof(decimal));

    private static void Prefix(IEnumerable<Creature>? targets, ValueProp props, Creature? dealer, CardModel? cardSource) =>
        CombatVfx.Hit(dealer, targets, props, cardSource);
}

[HarmonyPatch(typeof(NShivThrowVfx), nameof(NShivThrowVfx.Create),
    new[] { typeof(Creature), typeof(Creature), typeof(Color) })]
internal static class OriginalShivVisualPatch
{
    private static void Postfix(Creature owner, NShivThrowVfx? __result)
    {
        if (__result != null && Visuals.IsTarget(owner.Player?.Character) &&
            owner.GetCreatureNode()?.Visuals?.GetNodeOrNull(Visuals.NodeName) != null)
            __result.Visible = false; // Keep its native lifetime, screen shake and timing.
    }
}
