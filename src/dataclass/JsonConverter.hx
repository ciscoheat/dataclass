package dataclass;

import haxe.DynamicAccess;
import dataclass.Converter;
import dataclass.Converter.config;

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

class StringJsonConverter extends JsonConverter
{
	public static var current(default, default) : StringJsonConverter = new StringJsonConverter();
	
	public function new(?options : StringConverterOptions) {
		if(options == null) options = {};
		super(options);

		valueConverters.set('Int', new StringIntValueConverter());

		valueConverters.set('Date', new StringDateValueConverter(
			config(options.dateFormat, "%Y-%m-%d %H:%M:%S")
		));

		valueConverters.set('Float', new StringFloatValueConverter(
			config(options.floatDelimiter, ".")
		));

		valueConverters.set('Bool', new StringBoolValueConverter(
			if (Reflect.hasField(options, 'boolValues')) 
				{ tru: options.boolValues.tru, fals: options.boolValues.fals }
			else
				{ tru: "1", fals: "0" }
		));
	}
}