extends RefCounted

# Full-mode wall time -> accepted source time. Audio uses its own real clock.
# Monotone Hermite interpolation softens speed changes without skipping stages.
const CURVES:={
	"skill1":[[0.,0.],[.85,1.15],[1.15,1.5],[1.65,2.1],[1.8,2.3],[2.85,3.666666667],[3.04,3.9]],
	"skill2":[[0.,0.],[.75,1.1],[1.18,1.6],[1.65,2.12],[2.6,3.333333333],[3.4,4.3]],
	"unique":[[0.,0.],[.75,1.1],[1.0,1.4],[1.24,1.667],[1.78,2.333333],[2.12,2.866667],[3.82,5.566667],[4.25,6.216667],[4.61,6.616667],[5.27,7.366667],[6.03,8.166667],[6.67,9.166667],[7.4,10.2]]
}

static func _slope(keys:Array,i:int)->float:
	if i==0:return (float(keys[1][1])-float(keys[0][1]))/(float(keys[1][0])-float(keys[0][0]))
	if i==keys.size()-1:return (float(keys[i][1])-float(keys[i-1][1]))/(float(keys[i][0])-float(keys[i-1][0]))
	var a:float=(float(keys[i][1])-float(keys[i-1][1]))/(float(keys[i][0])-float(keys[i-1][0]))
	var b:float=(float(keys[i+1][1])-float(keys[i][1]))/(float(keys[i+1][0])-float(keys[i][0]))
	return 2.*a*b/(a+b)

static func sample(kind:String,t:float)->float:
	var keys:Array=CURVES[kind]
	if t<=0:return 0.
	for i in range(1,keys.size()):
		var a:Array=keys[i-1];var b:Array=keys[i]
		if t<=float(b[0]):
			var h:float=float(b[0])-float(a[0]);var u:float=(t-float(a[0]))/h
			return (2*u*u*u-3*u*u+1)*float(a[1])+(u*u*u-2*u*u+u)*h*_slope(keys,i-1)+(-2*u*u*u+3*u*u)*float(b[1])+(u*u*u-u*u)*h*_slope(keys,i)
	return float(keys[-1][1])+(t-float(keys[-1][0]))

static func inverse(kind:String,source:float)->float:
	var low:=0.;var high:float=maxf(source,float(CURVES[kind][-1][0]))+1.
	for i in range(40):
		var mid:float=(low+high)*.5
		if sample(kind,mid)<source:low=mid
		else:high=mid
	return (low+high)*.5
