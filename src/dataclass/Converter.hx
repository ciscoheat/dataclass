package dataclass;

import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.rtti.Meta;

import haxe.DynamicAccess;
import haxe.ds.ObjectMap;

using Lambda;
using StringTools;
using DateTools;

enum CircularReferenceHandling {
	ThrowException;
	SetToNull;
	TrackReferences;
}

typedef ConverterOptions = {
	?circularReferences : CircularReferenceHandling,
	?dateFormat : String
}

typedef StringConverterOptions = {
	> ConverterOptions,
	?floatDelimiter : String,
	?boolValues : { tru: String, fals: String },
}

typedef ValueConverter<From, To> = {
	function input(value : From) : To;
	function output(value : To) : From;
}

private typedef RefCountMap = Map<Int, Dynamic>;
private typedef RefAssignMap = Map<Int, Array<{obj: Int, field: String}>>;

class Rtti
{
	public static function rttiData<T : DataClass>(cls : Class<T>) : DynamicAccess<String> {
		var data : DynamicAccess<Array<Dynamic>> = Meta.getType(cls);
		return data.get("dataClassRtti")[0];
	}
}

class Converter
{
	static var directConversions = ['Int', 'Bool', 'Float', 'String'];
	
	public var valueConverters(default, null) : Map<String, ValueConverter<Dynamic, Dynamic>>;
	
	var circularReferences : CircularReferenceHandling;
	
	public macro static function config(optionField : Expr, defaultValue : Expr) {
		return switch optionField.expr {
			case EField(e, field): macro Reflect.hasField($e, $v{field}) ? $optionField : $defaultValue;
			case _: Context.error("Invalid config call, options object required.", Context.currentPos());
		}
	}
	
	public function new(?options : ConverterOptions) {
		if (options == null) options = {};

		valueConverters = new Map<String, ValueConverter<Dynamic, Dynamic>>();

		valueConverters.set('Date', new DateValueConverter(
			config(options.dateFormat, "%Y-%m-%dT%H:%M:%SZ")
		));
		
		this.circularReferences = config(options.circularReferences, ThrowException);
	}	
	
	public function toDataClass<T : DataClass>(cls : Class<T>, json : Dynamic) : T {
		var refCount = new RefCountMap();
		var refAssign = new RefAssignMap();
		var output = _toDataClass(cls, json, refCount, refAssign);
		
		assignReferences(refCount, refAssign);
		
		return output;
	}

	public function toAnonymousStructure<T : DataClass>(cls : Class<T>, json : Dynamic) : DynamicAccess<Dynamic> {
		var refCount = new RefCountMap();
		var refAssign = new RefAssignMap();
		var output = _toAnonymousStructure(cls, json, refCount, refAssign, 0, false);
		
		assignReferences(refCount, refAssign);
		
		return output;		
	}
	
	function assignReferences(refCount : RefCountMap, refAssign : RefAssignMap) {
		for (refId in refAssign.keys()) {
			for (data in refAssign.get(refId)) {
				//trace('ref $refId: assigning field ${data.field} to object ' + data.obj);
				Reflect.setProperty(refCount.get(refId), data.field, refCount.get(data.obj));
			}
		}
	}
		
	// currentId is used because _toDataClass will also track references but DataClass objects instead.
	function _toAnonymousStructure<T : DataClass>(cls : Class<T>, inputData : DynamicAccess<Dynamic>, 
		refCount : RefCountMap, refAssign : RefAssignMap, currentId : Int, toDataClass : Bool
	) : DynamicAccess<Dynamic> {
		var rtti = Converter.Rtti.rttiData(cls);
		var outputData : DynamicAccess<Dynamic> = {};

		if (circularReferences == TrackReferences && !toDataClass && inputData.exists("$id")) {
			currentId = cast inputData.get("$id");
			//trace('=== Converting ref $currentId');
		}

		for (field in rtti.keys()) {
			var input = inputData.get(field);
			var data = rtti[field];
			
			if (circularReferences == TrackReferences && 				
				input != null && 
				data.startsWith("DataClass<") 
				&& Reflect.hasField(input, "$ref")
			) {
				// Store reference for later assignment
				var refId : Int = cast Reflect.field(input, "$ref");
				var refData = { obj: refId, field: field };
				
				//trace('Found ref $refId in field $field');
				
				if (!refAssign.exists(currentId))
					refAssign.set(currentId, [refData]);
				else 
					refAssign.get(currentId).push(refData);
			} else {
				var output = toField(rtti[field], input, refCount, refAssign, toDataClass);				
				//trace(field + ': ' + input + ' -[' + rtti[field] + ']-> ' + output);
				outputData.set(field, output);
			}
		}
		
		if (circularReferences == TrackReferences && !toDataClass && currentId > 0) {
			refCount.set(currentId, outputData);
		}

		return outputData;
	}
	
	function _toDataClass<T : DataClass>(cls : Class<T>, json : Dynamic, refCount : RefCountMap, refAssign : RefAssignMap) : T {
		var inputData : DynamicAccess<Dynamic> = json;
		var currentId = 0;

		// Track references here instead of in _toAnonymousStructure, to assign the id afterwards
		if (circularReferences == TrackReferences && inputData.exists("$id")) {
			currentId = cast inputData.get("$id");
			//trace('=== Converting ref $currentId');
		}
		
		var outputData = _toAnonymousStructure(cls, inputData, refCount, refAssign, currentId, true);
		var output = Type.createInstance(cls, [outputData]);
		
		if (currentId > 0 && circularReferences == TrackReferences) {
			refCount.set(currentId, output);
		}

		return output;
	}
	
	function toField(data : String, value : Dynamic, refCount : RefCountMap, refAssign : RefAssignMap, toDataClass : Bool) : Dynamic {
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
			return [for (v in cast(value, Array<Dynamic>)) toField(arrayType, v, refCount, refAssign, toDataClass)];
		}
		else if (data.startsWith("Enum<")) {
			var enumT = enumType(data.substring(5, data.length - 1));
			return Type.createEnum(enumT, value);
		}
		else if (data.startsWith("DataClass<")) {			
			var classT = classType(data.substring(10, data.length - 1));
			return toDataClass 
				? _toDataClass(cast classT, value, refCount, refAssign)
				: _toAnonymousStructure(cast classT, value, refCount, refAssign, 0, toDataClass);
		}
		else if (data.startsWith("StringMap<")) {
			var mapType = data.substring(10, data.length - 1);
			
			var output = new StringMap<Dynamic>();
			var object : DynamicAccess<Dynamic> = cast value;
			
			for (key in object.keys()) {
				output.set(key, toField(mapType, object.get(key), refCount, refAssign, toDataClass));
			}
				
			return output;
		}		
		else if (data.startsWith("IntMap<")) {
			var mapType = data.substring(7, data.length - 1);
			
			var output = new IntMap<Dynamic>();
			var object : DynamicAccess<Dynamic> = cast value;
			
			for (key in object.keys()) {
				output.set(Std.parseInt(key), toField(mapType, object.get(key), refCount, refAssign, toDataClass));
			}
				
			return output;
		}		
		else 
			throw "Unsupported DataClass converter: " + data;
	}

	///////////////////////////////////////////////////////////////////////////
	
	public function fromDataClass(cls : DataClass) : DynamicAccess<Dynamic> {
		return _fromDataClass(cls, new ObjectMap<Dynamic, Int>(), 0);
	}
		
	function _fromDataClass(dataClass : DataClass, refs : ObjectMap<Dynamic, Int>, refcounter : Int) : DynamicAccess<Dynamic> {
		if (refs.exists(dataClass)) return switch circularReferences {
			case ThrowException: throw "Converting circular DataClass structure.";
			case SetToNull: null;
			case TrackReferences: { "$ref": refs.get(dataClass) };
		}
		else 
			refs.set(dataClass, ++refcounter);
		
		var outputData : DynamicAccess<Dynamic> = circularReferences == TrackReferences
			? { "$id": refcounter }
			: {};
			
		var rtti = Converter.Rtti.rttiData(Type.getClass(dataClass));
		
		for (field in rtti.keys()) {
			var input = Reflect.getProperty(dataClass, field);
			var output = convertToJsonField(rtti[field], input, refs, refcounter);
			
			//trace(field + ': ' + input + ' -[' + rtti[field] + ']-> ' + output);
			outputData.set(field, output);
		}
		
		if (circularReferences == SetToNull)
			refs.remove(dataClass);

		return outputData;
	}
	
	function convertToJsonField(data : String, value : Dynamic, refs : ObjectMap<Dynamic, Int>, refcounter : Int) : Dynamic {
		if (value == null) return value;

		if (valueConverters.exists(data)) {
			return valueConverters.get(data).output(cast value);
		}
		else if (directConversions.has(data)) {
			return value;
		}
		else if (data.startsWith("Array<")) {
			var arrayType = data.substring(6, data.length - 1);
			return [for (v in cast(value, Array<Dynamic>)) convertToJsonField(arrayType, v, refs, refcounter)];
		}
		else if (data.startsWith("Enum<")) {
			return Std.string(value);
		}
		else if (data.startsWith("DataClass<")) {
			return _fromDataClass(cast value, refs, refcounter);
		}
		else if (data.startsWith("StringMap<")) {
			var mapType = data.substring(10, data.length - 1);
			var map = cast(value, StringMap<Dynamic>);
			var output : DynamicAccess<Dynamic> = {};
			
			for (key in map.keys())
				output.set(key, convertToJsonField(mapType, map.get(key), refs, refcounter));
				
			return output;
		}		
		else if (data.startsWith("IntMap<")) {
			var mapType = data.substring(7, data.length - 1);
			var map = cast(value, IntMap<Dynamic>);
			var output : DynamicAccess<Dynamic> = { };
			
			for (key in map.keys())
				output.set(Std.string(key), convertToJsonField(mapType, map.get(key), refs, refcounter));
				
			return output;
		}
		else 
			throw "Unsupported DataClass converter: " + data;
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

class StringIntValueConverter
{
	public function new() { }

	public function input(input : String) : Int {
		return Std.parseInt(input.replace(" ", ""));
	}
	
	public function output(input : Int) : String {
		return Std.string(input);
	}
}

class StringBoolValueConverter
{
	var boolValues : { tru: String, fals: String };
	
	public function new(boolValues) {
		this.boolValues = boolValues;
	}

	public function input(input : String) : Bool {
		return boolValues.tru == input.trim();
	}
	
	public function output(input : Bool) : String {
		return input == true ? boolValues.tru : boolValues.fals;
	}
}

class StringFloatValueConverter
{
	var separator : String;
	var other : String;
	
	public function new(separator) {
		this.separator = separator;
		this.other = separator == "," ? "." : ",";
	}

	public function input(input : String) : Float {
		//trace('$input -> ' + input.replace(" ", "").replace(other, "").replace(separator, "."));
		return Std.parseFloat(input.replace(" ", "").replace(other, "").replace(separator, "."));
	}
	
	public function output(input : Float) : String {
		return Std.string(input).replace(".", separator);
	}
}

class StringCurrencyValueConverter
{
	var floatConverter : StringFloatValueConverter;
	var cents : Int;
	var separator : String;
	
	public function new(separator, cents : Int = 100) {
		this.floatConverter = new StringFloatValueConverter(separator);
		this.separator = separator;
		this.cents = cents;
	}

	public function input(input : String) : Int {
		return Std.int(floatConverter.input(input) * cents);
	}
	
	public function output(input : Int) : String {
		var maxlen = Std.string(input).length;
		var output = floatConverter.output(input / cents);
		var hasSeparator = output.indexOf(separator) >= 0;
		return output.substr(0, maxlen + (hasSeparator ? 1 : 0));
	}
}

class StringDateValueConverter
{
	var format : String;
	
	public function new(format) {
		this.format = format;
	}

	public function input(input : String) : Date {
		return Date.fromString(input);
	}
	
	public function output(input : Date) : String {
		return DateTools.format(input, format);
	}
}

class DateValueConverter
{
	var format : String;
	
	public function new(format : String) {
		this.format = format;
	}

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
		var time = format.endsWith("Z") ? DateTools.delta(input, -getTimeZone()) : input;
		return DateTools.format(time, format);
	}
	
	// Thanks to https://github.com/HaxeFoundation/haxe/issues/3268#issuecomment-52960338
	static function getTimeZone() {
		var now = Date.now();
		now = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
		return (24. * 3600 * 1000 * Math.round(now.getTime() / 24 / 3600 / 1000) - now.getTime());
	}
}
