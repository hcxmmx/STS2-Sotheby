using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Entities.Players;
using MegaCrit.Sts2.Core.Nodes.RestSite;
using MegaCrit.Sts2.Core.Nodes.Rooms;

namespace Hcxmmx.SothebySkin;

internal static class IdleRooms
{
    private static PackedScene? _scene;
    private static void Attach(Node2D root, string kind)
    {
        if (root.GetNodeOrNull("SothebyIdle") != null) return;
        var originals = new Godot.Collections.Array<Node2D>();
        foreach (var child in root.GetChildren())
            if (child is Node2D node && node.GetClass() == "SpineSprite") originals.Add(node);
        if (originals.Count == 0) return;
        _scene ??= ResourceLoader.Load<PackedScene>("res://Sotheby_Hcxmmx/RoomIdle.tscn");
        if (_scene == null) return;
        var idle = _scene.Instantiate<Node2D>();
        idle.Name = "SothebyIdle";
        root.AddChild(idle);
        // Keep native characters, animations, hitboxes and thought bubbles alive.
        // Hide only their drawing after the replacement's resources are ready.
        idle.CallDeferred("configure", originals, kind);
    }

    internal static void Merchant(NMerchantRoom room)
    {
        try
        {
            var players = AccessTools.Field(typeof(NMerchantRoom), "_players").GetValue(room) as IReadOnlyList<Player>;
            if (players == null || players.Count != room.PlayerVisuals.Count) return;
            for (int i = 0; i < players.Count; i++)
                if (Visuals.IsTarget(players[i].Character)) Attach(room.PlayerVisuals[i], "merchant");
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Merchant idle: " + ex.Message); }
    }

    internal static void Rest(NRestSiteCharacter character)
    {
        try
        {
            if (Visuals.IsTarget(character.Player?.Character)) Attach(character, "rest");
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Rest idle: " + ex.Message); }
    }
}

[HarmonyPatch(typeof(NMerchantRoom), nameof(NMerchantRoom._Ready))]
internal static class MerchantIdlePatch
{
    private static void Postfix(NMerchantRoom __instance) => IdleRooms.Merchant(__instance);
}

[HarmonyPatch(typeof(NRestSiteCharacter), nameof(NRestSiteCharacter._Ready))]
internal static class RestIdlePatch
{
    private static void Postfix(NRestSiteCharacter __instance) => IdleRooms.Rest(__instance);
}
