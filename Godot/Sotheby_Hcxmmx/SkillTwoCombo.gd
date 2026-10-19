extends RefCounted

# Runtime edit of skill2, source seconds. Only the initial raise is compressed;
# raised cast cycles and the final recovery keep their source playback speed.
const PREP_END := 1.10
const READY := 1.60
const CAST_END := 2.12
const ANIMATION_END := 3.3333333
const PREP_DURATION := .12
const MIX := .10
const KEEP_READY := .40
var phase := "idle"
var phase_start := 0.0
var at := 0.0
var pose_time := 0.0
var last_request := -100.0
var pending := false
var bridge_from := -1.0
var requests := 0
var preparations := 0
var cycles := 0
var rejoins := 0

func _phase(value: String, now: float) -> void:
	phase=value;phase_start=now

func request(now: float) -> void:
	requests+=1;last_request=now
	match phase:
		"idle":
			preparations+=1;pose_time=0;pending=false;_phase("prepare",now)
		"hold", "recover":_rejoin(now)
		_:pending=true

func _rejoin(now: float) -> void:
	bridge_from=pose_time;pending=false;rejoins+=1;_phase("bridge",now)

func advance(now: float) -> void:
	at=now
	var elapsed:=now-phase_start
	match phase:
		"prepare":
			pose_time=PREP_END*clampf(elapsed/PREP_DURATION,0,1)
			if elapsed>=PREP_DURATION:_phase("raise",now);pose_time=PREP_END
		"raise":
			pose_time=minf(PREP_END+elapsed,READY)
			if pose_time>=READY:cycles+=1;_phase("cast",now)
		"bridge":
			pose_time=READY
			if elapsed>=MIX:cycles+=1;bridge_from=-1;_phase("cast",now)
		"cast":
			pose_time=minf(READY+elapsed,CAST_END)
			if pose_time>=CAST_END:
				if pending:_rejoin(now)
				elif now-last_request>=KEEP_READY:_phase("recover",now)
				else:_phase("hold",now)
		"hold":
			pose_time=CAST_END
			if now-last_request>=KEEP_READY:_phase("recover",now)
		"recover":
			pose_time=minf(CAST_END+elapsed,ANIMATION_END)
			if pose_time>=ANIMATION_END:_phase("idle",now)

func pose() -> Dictionary:
	return {"time":pose_time,"from":bridge_from if phase=="bridge" else -1.0,"mix":at-phase_start if phase=="bridge" else MIX}
