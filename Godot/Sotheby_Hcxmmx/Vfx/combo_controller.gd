extends RefCounted

# Runtime edit of existing skill1: no .skel mutation. Times in source seconds.
const READY := 1.40
const THROW_END := 1.82
const ANIMATION_END := 2.30
const MIX := .08
const KEEP_READY := .40
var phase := "idle"
var at := 0.0
var pose_time := 0.0
var last_attack := -100.0
var phase_start := 0.0
var pending := false
var requests := 0
var preparations := 0
var throws := 0
var rejoins := 0
var bridge_from := -1.0
var prep_duration := .10
var history: Array = []

func request_attack(now: float) -> void:
	requests+=1;last_attack=now
	match phase:
		"idle":
			preparations+=1;bridge_from=0.0;_phase("prepare",now)
		"recover", "hold":
			_rejoin(now)
		_:
			# At most one pending BODY cycle. Every attack still gets its own VFX.
			pending=true

func _phase(value: String, now: float) -> void:
	phase=value;phase_start=now;history.append({"time":now,"phase":value})

func _rejoin(now: float) -> void:
	bridge_from=pose_time;rejoins+=1;pending=false;_phase("bridge",now)

func advance(now: float) -> void:
	at=now
	var dt:=now-phase_start
	match phase:
		"idle":pose_time=0.0
		"prepare":
			# Blend directly into the prepared pose instead of fast-forwarding
			# every gesture in the 1.4-second preparation.
			pose_time=READY
			if dt>=prep_duration:
				throws+=1;bridge_from=-1.0;_phase("throw",now);pose_time=READY
		"bridge":
			pose_time=READY
			if dt>=MIX:
				throws+=1;bridge_from=-1;_phase("throw",now)
		"throw":
			pose_time=minf(READY+dt,THROW_END)
			if pose_time>=THROW_END:
				if pending:_rejoin(now)
				elif now-last_attack>=KEEP_READY:_phase("recover",now)
				else:_phase("hold",now)
		"hold":
			pose_time=THROW_END
			if now-last_attack>=KEEP_READY:_phase("recover",now)
		"recover":
			pose_time=minf(THROW_END+dt,ANIMATION_END)
			if pose_time>=ANIMATION_END:bridge_from=-1;_phase("idle",now)

func pose() -> Dictionary:
	var idle_mix: bool=phase=="idle" and phase_start>0 and at-phase_start<MIX
	var mixed: bool=phase in ["bridge","prepare"] or idle_mix
	return {"animation":"idle" if phase=="idle" else "skill1","time":at-phase_start if phase=="idle" else pose_time,
		"from":ANIMATION_END if idle_mix else (bridge_from if mixed else -1.0),"mix":at-phase_start if mixed else MIX}
