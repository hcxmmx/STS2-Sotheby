extends RefCounted

const LENGTH:=2.7
const BURST:=1.6
const CUT:=1.2
const SOURCE_BURST:=7.366666667

# Output time / original time. A separate clock for every visual role keeps
# the original main burst at 1x while removing staging and repeated travel.
const CAST:Array=[[0.,0.],[.18,.9],[.40,1.4],[.50,1.67],[.85,2.3],[1.15,2.6],[2.7,4.15]]
const RIDE:Array=[[0.,0.],[.18,.9],[.40,1.4],[.50,1.67],[.85,2.3],[.90,3.25],[1.25,4.1],[2.7,5.55]]
const TREES:Array=[[0.,0.],[.18,.9],[.85,2.3],[.90,4.65],[1.25,5.4],[2.7,6.85]]
const IMPACT:Array=[[0.,5.5],[1.19999,5.5],[1.20,6.216666667],[1.25,6.616666667],[1.60,7.366666667],[2.7,8.466666667]]

static func map_keys(t:float,keys:Array)->float:
	if t<=float(keys[0][0]):return float(keys[0][1])
	for i in range(1,keys.size()):
		var a:Array=keys[i-1];var b:Array=keys[i]
		if t<=float(b[0]):return lerpf(float(a[1]),float(b[1]),(t-float(a[0]))/(float(b[0])-float(a[0])))
	return float(keys[-1][1])+t-float(keys[-1][0])

static func role(resource:String)->String:
	if resource=="sufubi_unique01":return "cast"
	if resource in ["sufubi_unique01bg","sufubi_unique01bg_02"]:return "trees"
	if resource in ["sufubi_unique01_special1","sufubi_unique01_special2"]:return "ride"
	if resource in ["sufubi_unique02_special1","sufubi_unique02_special2"]:return "second_carriage"
	if resource=="buff_huixue":return "conditional_heal"
	return "impact"

static func sample(t:float,kind:String)->float:
	match kind:
		"cast":return map_keys(t,CAST)
		"ride":return map_keys(t,RIDE)
		"trees":return map_keys(t,TREES)
		_:return map_keys(t,IMPACT)

static func weight(t:float,kind:String)->float:
	match kind:
		"cast":return 1.-smoothstep(.84,.95,t)
		"ride","trees":return 1.-smoothstep(1.20,1.32,t)
		"second_carriage","conditional_heal":return 0.
		_:return smoothstep(1.20,1.25,t)*(1.-smoothstep(2.35,2.70,t))

static func clocks(t:float,groups:Array,cut:float=-1.0)->Dictionary:
	var times:={};var cutoffs:={};var weights:={}
	for group in groups:
		var resource:String=group.source_resource
		if times.has(resource):continue
		var kind:=role(resource)
		var at:=sample(cut if cut>=0 else t,kind)
		times[resource]=at+maxf(0,t-cut) if cut>=0 else at
		cutoffs[resource]=sample(cut,kind) if cut>=0 else 10000.
		weights[resource]=weight(cut if cut>=0 else t,kind)
	return {"times":times,"cutoffs":cutoffs,"weights":weights}
