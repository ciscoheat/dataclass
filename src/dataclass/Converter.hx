package dataclass;

import haxe.DynamicAccess;
import haxe.rtti.Meta;

using StringTools;

typedef ValueConverter<From, To> = {
	function input(value : From) : To;
	function output(value : To) : From;
}

interface Converter 
{
	function toDataClass<T : DataClass>(cls : Class<T>, json : Dynamic) : T;
	function fromDataClass(cls : DataClass) : DynamicAccess<Dynamic>;
	
	var valueConverters(default, null) : Map<String, ValueConverter<Dynamic, Dynamic>>;
}

class Rtti
{
	public static function rttiData<T : DataClass>(cls : Class<T>) : DynamicAccess<String> {
		var data : DynamicAccess<Array<Dynamic>> = Meta.getType(cls);
		return data.get("dataClassRtti")[0];
	}
}

// TODO: Move to csv converter
typedef ConverterOptions = {
	?delimiter : String,
	?boolValues : { tru: String, fals: String },
	?dateFormat : String
}

class OldConverter
{
	///// Default configuration /////	
	public static var delimiter = ".";
	public static var boolValues = { tru: "1", fals: "0" };	
	public static var dateFormat = "%Y-%m-%d %H:%M:%S";
}

class DateValueConverter
{
	public function new() { }

	public function input(input : String) : Date {
		var s = input.trim();
		
		if (s.endsWith('Z')) {
			#if js
			return untyped __js__('new Date({0})', s);
			#else
			var isoZulu = ~/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$/;
			inline function d(pos : Int) return Std.parseInt(isoZulu.matched(pos));
			if (isoZulu.match(s)) {
				var hours = Std.int(Math.round(getTimeZone() / 1000 / 60 / 60));
				var minutes = hours * 60 - Std.int(Math.round(getTimeZone() / 1000 / 60));
				return new Date(d(1), d(2) - 1, d(3), d(4) + hours, d(5) + minutes, d(6));
			}
			#end
		}
		
		return Date.fromString(s);
	}
	
	public function output(input : Date) : String {
		var utc = DateTools.delta(input, -getTimeZone());
		return DateTools.format(utc, "%Y-%m-%dT%H:%M:%SZ");
	}
	
	// Thanks to https://github.com/HaxeFoundation/haxe/issues/3268#issuecomment-52960338
	static function getTimeZone() {
		var now = Date.now();
		now = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
		return (24. * 3600 * 1000 * Math.round(now.getTime() / 24 / 3600 / 1000) - now.getTime());
	}
}
