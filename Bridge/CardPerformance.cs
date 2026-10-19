using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Hooks;
using MegaCrit.Sts2.Core.Nodes.Combat;

namespace Hcxmmx.SothebySkin;

// Observe the validated card-play hook. Never wrap/replace a Task or modify
// the card, target, resources, damage, play count, or gameplay waiting.
[HarmonyPatch(typeof(Hook), nameof(Hook.BeforeCardPlayed))]
internal static class CardPerformancePatch
{
    private static void Prefix(CardPlay cardPlay)
    {
        try
        {
            var card = cardPlay.Card;
            var owner = card.Owner;
            if (!cardPlay.IsFirstInSeries || !Visuals.IsTarget(owner.Character)) return;
            var skin = owner.Creature.GetCreatureNode()?.Visuals?.GetNodeOrNull<Node2D>(Visuals.NodeName);
            if (skin == null) return;
            var targets = new Godot.Collections.Array<Godot.Collections.Dictionary>();
            IEnumerable<Creature> candidates = cardPlay.Target is { } target && target.Side != owner.Creature.Side
                ? new[] { target } : card.CombatState?.HittableEnemies ?? Enumerable.Empty<Creature>();
            foreach (var creature in candidates)
                if (creature.IsAlive && creature.GetCreatureNode() is { } node)
                    targets.Add(new Godot.Collections.Dictionary { ["node"] = node, ["ground"] = node.GetBottomOfHitbox() });
            skin.Call("card_played", card.Id.Entry, targets);
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Card performance: " + ex.Message); }
    }
}
