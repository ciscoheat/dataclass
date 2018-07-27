package dataclass;

import haxe.DynamicAccess;
import dataclass.Converter;

class TypedJsonConverter extends Converter
{
	public static function fromTypedJson<T : DataClass>(cls : Class<T>, json : Dynamic) : T {
		return current.toDataClass(cls, json);
	}

	public static function toTypedJson<T : DataClass>(cls : T) : DynamicAccess<Dynamic> {
		return current.fromDataClass(cls);
	}
	
	public static var current(default, default) : TypedJsonConverter = new TypedJsonConverter();
	
	///////////////////////////////////////////////////////////////////////////
	
	public function new(?options : ConverterOptions) {
		super(options);
		this.useClassInfo = true;
	}
}
