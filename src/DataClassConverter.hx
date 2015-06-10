import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;
using haxe.macro.ExprTools;

abstract DataClassConverter(String) from String to String {
	public inline function new(s : String) this = s;
	
	@:to public function toBool()
		return !(~/^(?:false|no|0|)$/i.match(this.trim()));
		
	@:to public function toInt()
		return Std.parseInt(~/\D/g.replace(this, ""));	

	@:to public function toDate()
		return Date.fromString(this.trim());

	@:to public function toFloat() {
		var delimiter = Std.int(Math.max(this.lastIndexOf(","), this.lastIndexOf(".")));
		var clean = function(s) return ~/\D/g.replace(s, "");
		
		if(delimiter == -1) return Std.parseFloat(clean(this));
		else return Std.parseFloat(clean(this.substr(0, delimiter)) + '.' + clean(this.substr(delimiter)));
	}

	@:from static public function fromBool(b : Bool)
		return new DataClassConverter(b ? "1" : "0");
	
	@:from static public function fromInt(i : Int)
		return new DataClassConverter(Std.string(i));

	@:from static public function fromDate(d : Date)
		return new DataClassConverter(DateTools.format(d, "%Y-%m-%d %H:%M:%S"));

	@:from static public function fromFloat(f : Float)
		return new DataClassConverter(Std.string(f).replace(".", ","));		
}
