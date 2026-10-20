using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;

namespace Hcxmmx.SothebySkin;

// Both host/client initialize through this method. Only its background is
// changed; saved values, ready/unready controls and networking remain native.
[HarmonyPatch(typeof(NMultiplayerLoadGameScreen), "AfterMultiplayerStarted")]
internal static class MultiplayerResumeBackground
{
    private static Texture2D? _texture;

    private static void Postfix(NMultiplayerLoadGameScreen __instance)
    {
        try
        {
            var container = Traverse.Create(__instance).Field("_bgContainer").GetValue<Control>();
            // The native method names this child from the LOCAL saved character.
            // A remote Silent player must not replace another character's page.
            var original = container?.GetNodeOrNull<Control>("SILENT_bg");
            if (container == null || original == null) return;
            _texture ??= ResourceLoader.Load<Texture2D>("res://Sotheby_Hcxmmx/Assets/ui/multiplayer_resume.png");
            if (_texture == null) return;
            const string name = "SothebyResumeBackground";
            if (container.GetNodeOrNull<TextureRect>(name) == null)
            {
                var background = new TextureRect
                {
                    Name = name,
                    Texture = _texture,
                    ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize,
                    StretchMode = TextureRect.StretchModeEnum.KeepAspectCovered,
                    MouseFilter = Control.MouseFilterEnum.Ignore,
                    FocusMode = Control.FocusModeEnum.None
                };
                container.AddChild(background);
                background.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            }
            original.Hide();
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Multiplayer resume background: " + ex.Message); }
    }
}
