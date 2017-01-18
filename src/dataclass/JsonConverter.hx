package dataclass;

import DataClass;
import haxe.DynamicAccess;

using Lambda;
using StringTools;
using DateTools;

class JsonConverter implements Converter
{
	public static function fromJson<T : DataClass>(cls : Class<T>, json : Dynamic) : T {
		return current.toDataClass(cls, json);
	}

	public static function toJson(cls : DataClass) : DynamicAccess<Dynamic> {
		return current.fromDataClass(cls);
	}
	
	public static var current(default, default) : JsonConverter = new JsonConverter();
	
	///////////////////////////////////////////////////////////////////////////
	
	static var directConversions = ['Int', 'Bool', 'Float', 'String'];
	
	public var valueConverters(default, null) : Map<String, Converter.ValueConverter<Dynamic, Dynamic>>;
	
	public function new() {
		valueConverters = new Map<String, Converter.ValueConverter<Dynamic, Dynamic>>();
		valueConverters.set('Date', new Converter.DateValueConverter());
	}
	
	public function toDataClass<T : DataClass>(cls : Class<T>, json : Dynamic) : T {
		var rtti = Converter.Rtti.rttiData(cls);
		var inputData : DynamicAccess<Dynamic> = json;
		var outputData : DynamicAccess<Dynamic> = {};
		
		for (field in rtti.keys()) {
			var input = inputData.get(field);
			var output = convertFromJsonField(rtti[field], input);
			
			//trace(field + ': ' + input + ' -[' + rtti[field] + ']-> ' + output);
			outputData.set(field, output);
		}

		return Type.createInstance(cls, [outputData]);
	}
	
	function convertFromJsonField(data : String, value : Dynamic) : Dynamic {
		if (value == null) return value;

		if (valueConverters.exists(data)) {
			return valueConverters.get(data).input(value);
		}
		// Check reserved structures
		else if (directConversions.has(data)) {
			return value;
		}
		else if (data.startsWith("Array<")) {
			var arrayType = data.substring(6, data.length - 1);
			return [for (v in cast(value, Array<Dynamic>)) convertFromJsonField(arrayType, v)];
		}
		else if (data.startsWith("Enum<")) {
			var enumT = enumType(data.substring(5, data.length - 1));
			return Type.createEnum(enumT, value);
		}
		else if (data.startsWith("DataClass<")) {
			var classT = classType(data.substring(10, data.length - 1));
			return fromJson(cast classT, value);
		}
		else 
			throw "Unsupported DataClass ORM mapping: " + data;
	}

	///////////////////////////////////////////////////////////////////////////
	
	public function fromDataClass(cls : DataClass) : DynamicAccess<Dynamic> {
		var rtti = Converter.Rtti.rttiData(Type.getClass(cls));
		var outputData : DynamicAccess<Dynamic> = {};
		
		for (field in rtti.keys()) {
			var input = Reflect.getProperty(cls, field);
			var output = convertToJsonField(rtti[field], input);
			
			//trace(field + ': ' + input + ' -[' + rtti[field] + ']-> ' + output);
			outputData.set(field, output);
		}

		return outputData;
	}
	
	function convertToJsonField(data : String, value : Dynamic) : Dynamic {
		if (value == null) return value;

		if (valueConverters.exists(data)) {
			return valueConverters.get(data).output(cast value);
		}
		else if (directConversions.has(data)) {
			return value;
		}
		else if (data.startsWith("Array<")) {
			var arrayType = data.substring(6, data.length - 1);
			return [for (v in cast(value, Array<Dynamic>)) convertToJsonField(arrayType, v)];
		}
		else if (data.startsWith("Enum<")) {
			return Std.string(value);
		}
		else if (data.startsWith("DataClass<")) {
			return toJson(cast value);
		}
		else 
			throw "Unsupported DataClass ORM mapping: " + data;
	}
	
	///// Type retrieval /////
	
	static var enumCache = new Map<String, Enum<Dynamic>>();
	static var classCache = new Map<String, Class<Dynamic>>();
	
	static function enumType(name : String) : Enum<Dynamic> {
		if (enumCache.exists(name)) return enumCache.get(name);
		
		var output = Type.resolveEnum(name);
		if (output == null) throw "Enum not found: " + name;

		enumCache.set(name, output);
		return output;
	}

	static function classType(name : String) : Class<Dynamic> {
		if (classCache.exists(name)) return classCache.get(name);
		
		var output = Type.resolveClass(name);
		if (output == null) throw "Class not found: " + name;

		classCache.set(name, output);
		return output;
	}
}
