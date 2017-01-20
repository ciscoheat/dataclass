package dataclass;

import haxe.DynamicAccess;
import dataclass.Converter;

using Lambda;
using StringTools;
using DateTools;

class JsonConverter extends Converter
{
	public static function fromJson<T : DataClass>(cls : Class<T>, json : Dynamic) : T {
		return current.toDataClass(cls, json);
	}

	public static function toJson<T : DataClass>(cls : T) : DynamicAccess<Dynamic> {
		return current.fromDataClass(cls);
	}
	
	public static var current(default, default) : JsonConverter = new JsonConverter();
	
	///////////////////////////////////////////////////////////////////////////
	
	public function new(?options : ConverterOptions) {
		super(options);
	}	
}
