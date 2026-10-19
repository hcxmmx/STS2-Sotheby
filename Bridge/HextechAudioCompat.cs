using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Nodes;
using MegaCrit.Sts2.Core.Saves;
using System.Reflection;
using System.Security.Cryptography;

namespace Hcxmmx.SothebySkin;

// Workaround for a reproduced WAV C# wrapper/native bind mismatch. No Hextech
// DLL/PCK is edited, and no rune selection, randomization or save method is patched.
internal static class HextechAudioCompat
{
    private const string ManagedHash = "0e4897ecdfb31456a97c7d8028dfb8d7dbdc632e2f73fc9b438d7b266a139289";
    private const string HextechHash = "830c9f21cfd2525e8b57f803854b9ea5c1fc20fc77e7e54ea45d32c264d27c93";
    private static readonly string[] Paths = ["res://HextechRunes/audio/hextechReroll.wav", "res://HextechRunes/audio/hextechSelectSilver.wav", "res://HextechRunes/audio/hextechSelectGold.wav", "res://HextechRunes/audio/hextechSelectPrismatic.wav"];
    private static MethodInfo? _target;
    private static Node? _bridge;

    private static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant();

    internal static void Initialize()
    {
        // This optional shim is limited to the exact managed library and Hextech
        // implementation observed in the crash logs, rather than future releases.
        var location = typeof(GodotObject).Assembly.Location;
        if (string.IsNullOrEmpty(location) || Hash(location) != ManagedHash) return;
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies()) TryInstall(assembly);
        if (_target == null) AppDomain.CurrentDomain.AssemblyLoad += OnAssemblyLoad;
    }

    private static void OnAssemblyLoad(object? sender, AssemblyLoadEventArgs args) => TryInstall(args.LoadedAssembly);

    private static void TryInstall(Assembly assembly)
    {
        if (_target != null || assembly.IsDynamic) return;
        var type = assembly.GetType("HextechRunes.HextechRuneSelectionScreen", false);
        if (type == null || string.IsNullOrEmpty(assembly.Location) || Hash(assembly.Location) != HextechHash) return;
        var method = AccessTools.DeclaredMethod(type, "PlaySfx", [typeof(string), typeof(AudioStreamPlayer).MakeByRefType(), typeof(string), typeof(float)]);
        if (method == null || method.IsStatic || method.ReturnType != typeof(void)) return;
        new Harmony("hcxmmx.sotheby.hextech-audio-compat").Patch(method, prefix: new HarmonyMethod(typeof(HextechAudioCompat), nameof(PlaySfxPrefix)));
        _target = method;
        AppDomain.CurrentDomain.AssemblyLoad -= OnAssemblyLoad;
        GD.Print("[SothebySkin] Hextech WAV compatibility enabled for verified 0.111.0 implementation (four selection/reroll sounds only).");

    }

    private static Node Bridge()
    {
        if (GodotObject.IsInstanceValid(_bridge)) return _bridge!;
        var scene = ResourceLoader.Load<PackedScene>("res://Sotheby_Hcxmmx/Compat/HextechAudio.tscn");
        _bridge = scene.Instantiate();
        Node root = (Node?)NGame.Instance ?? ((SceneTree)Engine.GetMainLoop()).Root;
        root.AddChild(_bridge);
        return _bridge;
    }

    private static bool PlaySfxPrefix(string path, ref AudioStreamPlayer? playerSlot, string playerName, float volumeScale)
    {
        if (!Paths.Contains(path)) return true;
        try
        {
            var bridge = Bridge();
            playerSlot = bridge.Call("get_player", playerName).As<AudioStreamPlayer>();
            var volume = Math.Clamp((SaveManager.Instance?.SettingsSave?.VolumeSfx ?? 1f) * volumeScale, 0f, 1f);
            if (!bridge.Call("play_file", path, playerSlot, volume).AsBool())
                GD.PushWarning("[SothebySkin] Hextech audio unavailable: " + path);
        }
        catch (Exception ex) { GD.PushWarning("[SothebySkin] Hextech audio compatibility: " + ex.Message); }
        // Do not fall back to a WAV wrapper already known to fail initialization.
        return false;
    }

}
