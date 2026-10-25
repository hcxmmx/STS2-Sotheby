using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Modding;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Models.CardPools;
using MegaCrit.Sts2.Core.Nodes.Screens.ModdingScreen;

namespace Hcxmmx.SothebySkin;

// The vanilla mod detail page has no configuration registry. Add one scoped
// button for our own entry; all controls and persistence ship inside our PCK.
internal static class SkinSettings
{
    private const string ButtonName = "SothebySettingsButton";
    internal static void Fill(NModInfoContainer container, Mod mod)
    {
        var button = container.GetNodeOrNull<Button>(ButtonName);
        bool ours = mod.manifest?.id == "SothebySkin";
        if (!ours) { if (button != null) button.Visible = false; return; }
        if (button == null)
        {
            button = new Button { Name = ButtonName, Text = "苏芙比设置" };
            button.AddThemeFontSizeOverride("font_size", 24);
            button.AddThemeFontOverride("font", ResourceLoader.Load<Font>("res://Sotheby_Hcxmmx/Cover/fonts/hwzs.ttf"));
            button.AddThemeColorOverride("font_color", new Color("e7e4d9"));
            button.AddThemeColorOverride("font_hover_color", new Color("ce763e"));
            foreach (var state in new[] { "normal", "hover", "pressed", "focus" })
            {
                var style = new StyleBoxFlat { BgColor = new Color("22271f"), BorderColor = new Color(state == "normal" ? "776a51" : "ce763e") };
                style.SetBorderWidthAll(1);
                button.AddThemeStyleboxOverride(state, style);
            }
            container.AddChild(button);
            button.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.TopRight);
            button.OffsetLeft = -230; button.OffsetRight = -12;
            // Native title uses a 92px-high area and can shrink/wrap. Place
            // the button below it so long localized names remain readable.
            button.OffsetTop = 116; button.OffsetBottom = 168;
            button.Pressed += () => Open(container);
        }
        button.Show();
    }

    internal static void Clear(NModInfoContainer container) => container.GetNodeOrNull<Button>(ButtonName)?.Hide();

    internal static void Open(Node owner)
    {
        try
        {
            if (owner.GetNodeOrNull("SothebySettingsPanel") != null) return;
            var script = ResourceLoader.Load<GDScript>("res://Sotheby_Hcxmmx/SettingsPanel.gd");
            if (script?.New().AsGodotObject() is not CanvasLayer panel) return;
            panel.Name = "SothebySettingsPanel";
            // Use Silent's registered pool, including additions to that pool.
            var cards = new Godot.Collections.Array<Godot.Collections.Dictionary>();
            foreach (var card in ModelDb.CardPool<SilentCardPool>().AllCards.OrderBy(card => card.Title).DistinctBy(card => card.Id.Entry))
                cards.Add(new Godot.Collections.Dictionary { ["id"] = card.Id.Entry, ["title"] = card.Title });
            panel.Call("set_cards", cards);
            owner.AddChild(panel);
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Settings: " + ex); }
    }
}

[HarmonyPatch(typeof(NModInfoContainer), nameof(NModInfoContainer.Fill))]
internal static class ModSettingsButtonPatch
{
    private static void Postfix(NModInfoContainer __instance, Mod mod) => SkinSettings.Fill(__instance, mod);
}

[HarmonyPatch(typeof(NModInfoContainer), "Clear")]
internal static class ModSettingsClearPatch
{
    private static bool Prepare() => AccessTools.DeclaredMethod(typeof(NModInfoContainer), "Clear") != null;

    private static void Postfix(NModInfoContainer __instance) => SkinSettings.Clear(__instance);
}
