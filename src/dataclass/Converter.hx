package dataclass;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
using haxe.macro.ExprTools;
using Lambda;
#end

import haxe.DynamicAccess;
import haxe.rtti.Meta;

using StringTools;
using Converter.StringConverter;

typedef ValueConverter<T> = {
	function from(string : String) : T;
	function to(value : T) : String;
}

// TODO: Move to ORM configuration
typedef ConverterOptions = {
	?delimiter : String,
	?boolValues : { tru: String, fals: String },
	?dateFormat : String
}

class Converter
{
	///// Default configuration /////	
	public static var delimiter = ".";
	public static var boolValues = { tru: "1", fals: "0" };	
	public static var dateFormat = "%Y-%m-%d %H:%M:%S";
}

class RecursiveConverter
{
	/**
	 * When loading json from a document DB for example.
	 */
	public static function convertRecursive<T : DataClass>(cls : Class<T>, data : Dynamic, ?delimiter : String) : T {
		//trace('=== Recursive converting ' + Type.getClassName(cls));
		
		// Allow for constructors that takes an array?
		//if (Std.is(data, Array)) return Type.createInstance(cls, [data]);
		
		var convData : DynamicAccess<String> = Meta.getType(cls).fullConv[0];
		var output : DynamicAccess<Dynamic> = { };
		
		for (field in convData.keys()) if (Reflect.hasField(data, field)) {
			var value = Reflect.field(data, field);
			var dataClassName = convData.get(field);

			// Is a normal value or object
			if (value == null || dataClassName.length == 0) {
				output.set(field, value);
				continue;
			} else if (dataClassName.startsWith('*')) {
				// Convert basic type
				//trace('Converting basic type $dataClassName for field $field');
				output.set(field, DynamicObjectConverter.toCorrectValue(dataClassName.substr(1), value, true, delimiter, field));
				continue;
			}
			
			// Is a DataClass, convert it.
			var isArray = dataClassName.startsWith('[');
			var name = isArray ? dataClassName.substr(1) : dataClassName;
			
			var type = Type.resolveClass(name);			
			if (type == null) throw 'DataClass not found: $name';
			
			if (isArray) {
				//trace('Converting $field -> Array<$name>');
				output.set(field, [for (v in cast(value, Array<Dynamic>)) convertRecursive(type, v)]);
			} else {
				//trace('Converting $field -> $name');
				output.set(field, convertRecursive(type, value));
			}
		}
		
		//trace('=====');
		return Type.createInstance(cls, [output]);
	}
}

class DynamicObjectConverter 
{
	public static function convertTo<T : DataClass>(from : DataClass, to : Class<T>) : T {
		try return DynamicObjectConverter.fromDynamic(to, DynamicObjectConverter.toAnonymousStructure(from))
		catch (e : Dynamic) throw "Conversion to " + Type.getClassName(to) + " failed: " + from;
	}

	/**
	 * Maps all public DataClass fields to an anonymous structure
	 */
	public static function toAnonymousStructure(from : DataClass) : Dynamic {
		var meta = Meta.getType(Type.getClass(from));
		var fields : Array<String> = cast meta.dataClassFields;
		
		var data = {};
		for (f in fields) Reflect.setField(data, f, Reflect.getProperty(from, f));		
		return data;
	}

	/**
	 * Converts a DataClass to string values according to ConverterOptions
	 */
	public static function toStringData(o : DataClass, ?opts : ConverterOptions) : Dynamic<String> {
		var options:ConverterOptions = opts == null ? {
		        delimiter: Converter.delimiter,
		        boolValues: Converter.boolValues,
		        dateFormat: Converter.dateFormat
		    } : {
		        delimiter: opts.delimiter != null ? opts.delimiter : Converter.delimiter,
		        boolValues: opts.boolValues != null ? opts.boolValues : Converter.boolValues,
		        dateFormat: opts.dateFormat != null ? opts.dateFormat : Converter.dateFormat
		    };
		
		var cls = Type.getClass(o);
		var columns : DynamicAccess<String> = cast Meta.getType(cls).convertTo[0];
		var output = {};

		for (fieldName in columns.keys()) {
			var convert = columns.get(fieldName);
			if (convert == null) continue;
			
			var data : Dynamic = Reflect.getProperty(o, fieldName);
			var converted : String = data == null ? null : switch convert {
				case "Bool" if(Std.is(data, Bool)): BoolConverter.toString(data, options.boolValues);
				case "Date" if(Std.is(data, Date)): DateConverter.toStringFormat(data, options.dateFormat);
				case "Int" if(Std.is(data, Int)): IntConverter.toString(data);
				case "Float" if(Std.is(data, Float)): FloatConverter.toString(data, options.delimiter);
				case "String" if(Std.is(data, String)): data;
				
				case _:	throw "DynamicObjectConverter.toDynamic: Invalid type '" 
								+ Type.typeof(data) + '\' ($convert) for field $fieldName';
			};

			Reflect.setField(output, fieldName, converted);
		}		
		
		return output;
	}

	/**
	 * Converts a Dynamic object to a DataClass.
	 */
	public static function fromDynamic<T : DataClass>(cls : Class<T>, data : {}, ?passThrough : Array<String>, ?delimiter : String) : T {
		return Type.createInstance(cls, [toCorrectTypes(cls, data, passThrough, delimiter)]);
	}

	/**
	 * Converts a Dynamic object to another Dynamic object with correct types for a specified DataClass.
	 */
	public static function toCorrectTypes<T : DataClass>(cls : Class<T>, data : {}, ?passThrough : Array<String>, ?delimiter : String) : Dynamic {
		if (passThrough == null) passThrough = [];
		
		//trace("===== fromDynamicObject: " + Type.getClassName(cls));
		//trace(data);
		
		// Set in Builder.hx
		var columns : DynamicAccess<String> = cast Meta.getType(cls).convertFrom[0];
		var output = {};

		for(pass in passThrough) {
			Reflect.setField(output, pass, Reflect.field(data, pass));
		}

		for (fieldName in columns.keys()) if(Reflect.hasField(data, fieldName)) {
			//trace('Converting field $fieldName: ');
			
			var convert = columns.get(fieldName);
			if (convert == null) continue;
			
			// java requires explicit Dynamic here.
			var data : Dynamic = Reflect.field(data, fieldName);
			//trace('$data to $convert');
			
			var converted = toCorrectValue(convert, data, true, delimiter, fieldName);
			
			//trace('Result: $converted');
			
			Reflect.setField(output, fieldName, converted);
		}

		return output;
	}
	
	@:allow(dataclass.RecursiveConverter)
	private static function toCorrectValue(type : String, data : Dynamic, throwIfNotSupported : Bool, ?delimiter : String, ?fieldName : String) : Dynamic {
		return data == null ? null : switch type {
			case "String": Std.string(data);

			case "Bool" if(Std.is(data, Bool)):   data;
			case "Bool" if(Std.is(data, String)): StringConverter.toBool(data);

			case "Int" if(Std.is(data, Int)):    data;
			case "Int" if(Std.is(data, String)): StringConverter.toInt(data, delimiter);

			case "Date" if(Std.is(data, Date)):   data;
			case "Date" if(Std.is(data, String)): StringConverter.toDate(data);
			case "Date" if(Std.is(data, Float)):  FloatConverter.toDate(data);
			case "Date" if(Std.is(data, Int)):    IntConverter.toDate(data);

			case "Float" if(Std.is(data, Float)):  data;
			case "Float" if(Std.is(data, String)): StringConverter.toFloat(data, delimiter);
			
			case _:
				if (throwIfNotSupported)	
					throw "Invalid type '" + Type.typeof(data) + '\' ($type)' + (fieldName == null ? '' : ' for field $fieldName');
				data;
		};		
	}
	
	///////////////////////////////////////////////////////////////////////////
	
	public static var supportedTypes(default, null) = ["Bool" => true, "Date" => true, "Int" => true, "Float" => true, "String" => true];
}

// TODO: Move to ORM
class ColumnConverter {
	public static function fromColMetaData<T : DataClass>(cls : Class<T>, data : Iterable<String>, ?delimiter : String) : T {
		var columns = Meta.getFields(cls);
		var input = Lambda.array(data);
		var output = {};
		
		for (fieldName in Reflect.fields(columns)) {
			var field = Reflect.field(columns, fieldName);
			var col = Reflect.field(field, "col");
			if(col != null)	Reflect.setField(output, fieldName, input[col[0] - 1]);
		}
		
		return DynamicObjectConverter.fromDynamic(cls, output, delimiter);
	}
	
	public static function fromColumnData<T : DataClass>(cls : Class<T>, columns : Iterable<String>, data : Iterable<String>, ?delimiter : String) : T {
		var input = Lambda.array(data);
		var output = {};
		var i = 0;
		
		for (fieldName in columns) {
			Reflect.setField(output, fieldName, input[i++]);
		}
		
		return DynamicObjectConverter.fromDynamic(cls, output, delimiter);
	}
}

// TODO: Move and allow custom converters?
class StringConverter
{
	public static function toBool(s : String) : Bool
		return !(~/^(?:false|no|0|)$/i.match(s.trim()));
		
	public static function toDate(s : String) : Date {
		var s = s.trim();
		
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
		
	public static function toInt(s : String, ?delimiter : String) : Int {
		if (delimiter == null) delimiter = Converter.delimiter;	

		delimiter = delimiter == "" 
			? s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.'
			: delimiter;
		
		return Std.parseInt(s.replace(delimiter, "."));
	}

	public static function toFloat(s : String, ?delimiter : String) : Float {
		if (delimiter == null) delimiter = Converter.delimiter;
		
		delimiter = delimiter == "" 
			? s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.'
			: delimiter;

		var delimPos = s.lastIndexOf(delimiter);		
		var clean = function(s) return ~/[^\deE+-]/g.replace(s, "");
		
		return Std.parseFloat(delimPos == -1
			? clean(s)
			: clean(s.substr(0, delimPos)) + "." + clean(s.substr(delimPos))
		);		
	}
	
	// Thanks to https://github.com/HaxeFoundation/haxe/issues/3268#issuecomment-52960338
	static function getTimeZone() {
		var now = Date.now();
		now = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
		return (24. * 3600 * 1000 * Math.round(now.getTime() / 24 / 3600 / 1000) - now.getTime());
	}	
}

class BoolConverter {
	public static function toString(b : Bool, ?boolValues : {tru: String, fals: String}) {
		if (boolValues == null) boolValues = Converter.boolValues;
		return b ? boolValues.tru : boolValues.fals;
	}
}

class IntConverter {
	public static function toString(i : Int)
		return Std.string(i);
		
	public static function toDate(i : Int)
		return Date.fromTime(i);
}

class DateConverter {
	public static function toStringFormat(d : Date, ?format : String) {
		if (format == null) format = Converter.dateFormat;
		return DateTools.format(d, format);
	}
}

class FloatConverter {
	public static function toString(f : Float, ?delimiter : String) {
		if (delimiter == null) delimiter = Converter.delimiter;
		return Std.string(f).replace(".", delimiter);
	}
	
	public static function toDate(f : Float)
		return Date.fromTime(f);
}
