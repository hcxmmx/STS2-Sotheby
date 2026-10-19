#if SELECT_DIAGNOSTIC
using Godot;
using HarmonyLib;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Nodes;
using MegaCrit.Sts2.Core.Nodes.Screens.CharacterSelect;
using MegaCrit.Sts2.Core.Nodes.Screens.MainMenu;

namespace Hcxmmx.SothebySkin;

// Only compiled for the local diagnostic run. Absent from release assemblies.
internal static class SelectDiagnostic
{
    internal static bool ProbeDeferred = false;
    private static SceneTree _tree = null!;
    private static Godot.Timer _timer = null!;
    private static NCharacterSelectScreen? _screen;
    private static NMainMenuSubmenuStack? _stack;
    private static CharacterModel? _model;
    private static int _ticks, _phase, _next;
    private static bool _pushed;
    private static readonly string Output = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "SothebySelectDiagnostic");

    internal static void Start(SceneTree tree)
    {
        if (!OS.GetCmdlineUserArgs().Contains("--sotheby-select-diagnostic")) { ProbeDeferred = false; return; }
        _tree = tree;
        _timer = new Godot.Timer { Name="SothebySelectDiagnostic", WaitTime=.5, Autostart=true };
        _timer.Timeout += Tick;
        tree.Root.CallDeferred(Node.MethodName.AddChild, _timer);
    }

    private static T? Find<T>(Node node) where T:Node
    {
        if (node is T found) return found;
        foreach (var child in node.GetChildren())
            if (Find<T>(child) is T result) return result;
        return null;
    }

    private static void Tick()
    {
        try
        {
            _ticks++;
            if (_ticks > 150) throw new Exception("Main-menu diagnostic timed out.");
            if (_ticks < 70 || _ticks < _next) return;
            if (_phase==0)
            {
                _stack=Find<NMainMenuSubmenuStack>(_tree.Root);
                if (_stack==null) return;
                _screen=_stack.Peek() as NCharacterSelectScreen ?? _stack.GetSubmenuType<NCharacterSelectScreen>();
                var bg=Traverse.Create(_screen).Field("_bgContainer").GetValue<Control>();
                if (bg==null) return;
                GD.Print("[SothebySelectDiagnostic] Before opening: sourceInside="+_screen.IsInsideTree()+", bgInside="+bg.IsInsideTree()+", hostInside="+bg.GetParent().IsInsideTree());
                if (!ReferenceEquals(_stack.Peek(), _screen))
                {
                    _screen.InitializeSingleplayer();
                    _stack.Push(_screen);
                    _pushed=true;
                }
                var buttons=Traverse.Create(_screen).Field("_charButtonContainer").GetValue<Control>();
                var button=buttons.GetChildren().OfType<NCharacterSelectButton>().First(b=>!b.IsLocked && Visuals.IsTarget(b.Character));
                _model=button.Character;
                button.Select();
                _phase=1;_next=_ticks+4;
                return;
            }
            var host=Visuals.SelectHost(_screen!);
            var cover=host.GetNodeOrNull<Control>(Visuals.NodeName);
            if (_phase==1)
            {
                GD.Print("[SothebySelectDiagnostic] After old deferred path: cover="+(cover!=null)+", sourceInside="+_screen!.IsInsideTree()+", hostInside="+host.IsInsideTree());
                ProbeDeferred=false;
                if (cover==null) Visuals.Select(_screen!,_model!);
                _phase=2;_next=_ticks+4;
                return;
            }
            bool passed=cover!=null && cover.IsVisibleInTree() && cover.Call("is_ready").AsBool();
            string image=System.IO.Path.Combine(Output,"real_select.png");
            _tree.Root.GetTexture().GetImage().SavePng(image);
            System.IO.File.WriteAllText(System.IO.Path.Combine(Output,"real_select.json"),System.Text.Json.JsonSerializer.Serialize(new {
                passed, source_inside=_screen!.IsInsideTree(),host_inside=host.IsInsideTree(),host_path=host.GetPath().ToString(),
                visible=cover?.IsVisibleInTree(),self_visible=cover?.Visible,host_visible=host.Visible,active=cover?.Get("active").AsBool(),
                ready=cover?.Call("is_ready").AsBool(),image,run_started=false,scope="Actual installed game and enabled mods; menu selection only"
            },new System.Text.Json.JsonSerializerOptions { WriteIndented=true }));
            GD.Print("[SothebySelectDiagnostic] REAL_SELECT_PASSED="+passed);
            _timer.Stop();
            if (_pushed)_stack!.Pop();
            NGame.Instance?.Quit();
        }
        catch(Exception ex)
        {
            GD.PushError("[SothebySelectDiagnostic] "+ex);
            System.IO.File.WriteAllText(System.IO.Path.Combine(Output,"real_select_error.txt"),ex.ToString());
            _timer.Stop();
            NGame.Instance?.Quit();
        }
    }
}
#endif
