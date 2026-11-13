using System.Reflection;
using System.Reflection.Emit;
using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;
using MegaCrit.Sts2.Core.Nodes.Vfx.Utilities;

namespace Hcxmmx.SothebySkin;

// Replace only these two call sites in selection. No global audio/shake hooks,
// mutable character properties or changes to selection/lobby behavior.
[HarmonyPatch(typeof(NCharacterSelectScreen), nameof(NCharacterSelectScreen.SelectCharacter))]
internal static class CharacterSelectPresentation
{
    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions, MethodBase __originalMethod)
    {
        var sound = AccessTools.Method(typeof(SfxCmd), nameof(SfxCmd.Play), [typeof(string), typeof(float)]);
        var shake = AccessTools.Method(typeof(NGame), nameof(NGame.ScreenShake), [typeof(ShakeStrength), typeof(ShakeDuration), typeof(float)]);
        var parameters = __originalMethod.GetParameters();
        var character = parameters.SingleOrDefault(parameter => parameter.ParameterType == typeof(CharacterModel));
        var button = parameters.Single(parameter => parameter.ParameterType == typeof(NCharacterSelectButton));
        var getCharacter = AccessTools.PropertyGetter(typeof(NCharacterSelectButton), nameof(NCharacterSelectButton.Character));
        int sounds = 0, shakes = 0;
        foreach (var original in instructions)
        {
            string? replacement = original.Calls(sound) ? nameof(PlaySelectionSound) :
                original.Calls(shake) ? nameof(ShakeSelection) : null;
            if (replacement == null) { yield return original; continue; }
            if (replacement == nameof(PlaySelectionSound)) sounds++; else shakes++;
            // Preserve branch targets on the first added instruction.
            yield return new CodeInstruction(OpCodes.Ldarg, (character ?? button).Position + 1).MoveLabelsFrom(original).MoveBlocksFrom(original);
            if (character == null) yield return new CodeInstruction(OpCodes.Callvirt, getCharacter);
            yield return new CodeInstruction(OpCodes.Call, AccessTools.Method(typeof(CharacterSelectPresentation), replacement));
        }
        if (sounds != 1 || shakes != 1)
            throw new InvalidOperationException($"Unexpected character selection presentation calls: sound={sounds}, shake={shakes}");
    }

    private static void PlaySelectionSound(string sound, float volume, CharacterModel character)
    {
        if (!Visuals.IsTarget(character)) SfxCmd.Play(sound, volume);
    }

    private static void ShakeSelection(NGame game, ShakeStrength strength, ShakeDuration duration, float angle, CharacterModel character)
    {
        if (!Visuals.IsTarget(character)) game.ScreenShake(strength, duration, angle);
    }
}
