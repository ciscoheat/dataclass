package dataclass;

import DataClass;
import haxe.DynamicAccess;
import haxe.rtti.Meta;

using StringTools;

typedef ValueConverter<From, To> = {
	function input(value : From) : To;
	function output(value : To) : From;
}

interface Converter
{
	function toDataClass<T : DataClass>(cls : Class<T>, input : Dynamic) : T;
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
