using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using HarmonyLib;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Commands.Builders;

namespace Hcxmmx.SothebySkin;

// Observe actual damage dispatch in v0.113, including an inlined Damage method.
// Preserve the evaluated arguments, original call, returned task and waits.
[HarmonyPatch]
internal static class AttackDamageDispatchPatch
{
    private static readonly Type State = typeof(AttackCommand).GetMethod(nameof(AttackCommand.Execute))!
        .GetCustomAttribute<AsyncStateMachineAttribute>()!.StateMachineType;
    private static bool Prepare() => AttackDamagePatch.ObserveAtCallSite;
    private static MethodBase TargetMethod() => AccessTools.Method(State, "MoveNext");

    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions, ILGenerator generator)
    {
        var damage = AttackDamagePatch.TargetMethod();
        var hit = AccessTools.Method(typeof(CombatVfx), nameof(CombatVfx.Hit));
        foreach (var instruction in instructions)
        {
            if (instruction.Calls(damage))
            {
                // Save the native call's evaluated arguments exactly once.
                // The explicit observer survives JIT inlining of CreatureCmd.Damage.
                var damageArguments = damage.GetParameters().Select(parameter => generator.DeclareLocal(parameter.ParameterType)).ToArray();
                for (int i = damageArguments.Length - 1; i >= 0; i--)
                {
                    var save = new CodeInstruction(OpCodes.Stloc, damageArguments[i]);
                    if (i == damageArguments.Length - 1) save.MoveLabelsFrom(instruction).MoveBlocksFrom(instruction);
                    yield return save;
                }
                yield return new CodeInstruction(OpCodes.Ldloc, damageArguments[4]); // dealer
                yield return new CodeInstruction(OpCodes.Ldloc, damageArguments[1]); // targetData
                yield return new CodeInstruction(OpCodes.Ldloc, damageArguments[3]); // props
                yield return new CodeInstruction(OpCodes.Ldloc, damageArguments[5]); // cardSource
                yield return new CodeInstruction(OpCodes.Call, hit);
                foreach (var argument in damageArguments) yield return new CodeInstruction(OpCodes.Ldloc, argument);
                yield return instruction;
                continue;
            }
            yield return instruction;
        }
    }
}
