using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Context;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Nodes.Combat;
using System.Reflection;

namespace Hcxmmx.SothebySkin;

// Observe actual hand-card play input, never hover, CanPlay, tasks or gameplay RNG.
[HarmonyPatch]
internal static class CardSelectionPatch
{
    private static IEnumerable<MethodBase> TargetMethods()
    {
        yield return AccessTools.Method(typeof(NMouseCardPlay), nameof(NMouseCardPlay.Start));
        yield return AccessTools.Method(typeof(NControllerCardPlay), nameof(NControllerCardPlay.Start));
    }

    // Prefix so synchronous cancellation/confirmation inside Start is observed.
    private static void Prefix(NCardPlay __instance)
    {
        try
        {
            var card = __instance.Holder?.CardModel;
            var owner = card?.Owner;
            if (card == null || owner == null || !LocalContext.IsMe(owner.Creature) ||
                !Visuals.IsTarget(owner.Character)) return;
            var skin = owner.Creature.GetCreatureNode()?.Visuals?.GetNodeOrNull<Node2D>(Visuals.NodeName);
            if (skin == null || !GodotObject.IsInstanceValid(skin)) return;
            long ticket = (long)__instance.GetInstanceId();
            bool ended = false;
            void End(bool committed)
            {
                if (ended) return;
                ended = true;
                if (!GodotObject.IsInstanceValid(skin) || !skin.IsInsideTree()) return;
                try { skin.Call("card_selection_end", ticket, committed); }
                catch (Exception ex) { GD.PushWarning("[SothebySkin] Selection end: " + ex.Message); }
            }
            __instance.Connect(NCardPlay.SignalName.Finished, Callable.From<bool>(End), (uint)GodotObject.ConnectFlags.OneShot);
            __instance.TreeExiting += () => End(false);
            skin.Call("card_selection_begin", ticket, card.Id.Entry, card.IsUpgraded);
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Selection begin: " + ex.Message); }
    }
}
