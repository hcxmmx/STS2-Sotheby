using System.Reflection;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes.Combat;
using MegaCrit.Sts2.Core.Nodes.Events.Custom;
using System.Reflection.Emit;
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

    internal static void FakeMerchant(NCreatureVisuals visuals)
    {
        try
        {
            if (!GodotObject.IsInstanceValid(visuals) || !visuals.IsInsideTree()) return;
            for (Node? parent = visuals.GetParent(); parent != null; parent = parent.GetParent())
                if (parent is NFakeMerchant)
                {
                    Attach(visuals, "fake_merchant");
                    return;
                }
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Fake merchant idle: " + ex.Message); }
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

[HarmonyPatch(typeof(NFakeMerchant), "AfterRoomIsLoaded")]
internal static class FakeMerchantIdlePatch
{
    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions)
    {
        var create = AccessTools.Method(typeof(CharacterModel), nameof(CharacterModel.CreateVisuals));
        var observe = AccessTools.Method(typeof(FakeMerchantIdlePatch), nameof(ObserveCreated));
        foreach (var instruction in instructions)
        {
            var method = instruction.operand as MethodInfo;
            bool skinWrapper = method?.DeclaringType?.FullName is
                "Hcxmmx.AKnightSkin.FakeMerchantIdlePatch" or
                "Hcxmmx.SchneiderSkin.FakeMerchantIdlePatch";
            bool wrappedCreation = skinWrapper && method!.IsStatic && method.Name == "CreateVisuals" &&
                method.ReturnType == typeof(NCreatureVisuals) &&
                method.GetParameters() is { Length: 1 } parameters && parameters[0].ParameterType == typeof(CharacterModel);
            if (instruction.Calls(create) || wrappedCreation)
            {
                // Preserve the incoming creator, including another skin's wrapper.
                // Keep its model beside the returned visuals for our observer.
                yield return new CodeInstruction(OpCodes.Dup).MoveLabelsFrom(instruction).MoveBlocksFrom(instruction);
                yield return instruction;
                yield return new CodeInstruction(OpCodes.Call, observe);
            }
            else yield return instruction;
        }
    }

    private static NCreatureVisuals ObserveCreated(CharacterModel model, NCreatureVisuals visuals)
    {
        if (Visuals.IsTarget(model) && GodotObject.IsInstanceValid(visuals))
        {
            GD.Print("[SothebySkin] Fake merchant visuals observed for " + model.Id.Entry);
            Callable.From(() => IdleRooms.FakeMerchant(visuals)).CallDeferred();
        }
        return visuals;
    }
}
