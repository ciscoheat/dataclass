package dataclass;

import haxe.rtti.Meta;

using StringTools;
using Converter.StringConverter;

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

class DynamicObjectConverter {
	public static var supportedTypes(default, null) = ["Bool", "Date", "Int", "Float", "String"];

	static function convertTo(fieldName, columns) {
		var field = Reflect.field(columns, fieldName);
		return Reflect.hasField(field, "convertTo") ? Reflect.field(field, "convertTo")[0] : null;
	}

	public static function toDynamic(o : DataClass, ?opts : ConverterOptions) : Dynamic<String> {
		var options = {
			delimiter: opts.delimiter != null ? opts.delimiter : Converter.delimiter,
			boolValues: opts.boolValues != null ? opts.boolValues : Converter.boolValues,
			dateFormat: opts.dateFormat != null ? opts.dateFormat : Converter.dateFormat,
		}
		
		var cls = Type.getClass(o);
		var columns = Meta.getFields(cls);
		var output = { };

		for (fieldName in Reflect.fields(columns)) {
			var convert = convertTo(fieldName, columns);
			if (convert == null) continue;
			
			var data : Dynamic = Reflect.getProperty(o, fieldName);
			var converted : String = data == null ? null : switch convert {
				case "Bool" if(Std.is(data, Bool)): BoolConverter.toString(data, options.boolValues);
				case "Date" if(Std.is(data, Date)): DateConverter.toStringFormat(data, options.dateFormat);
				case "Int" if(Std.is(data, Int)): IntConverter.toString(data);
				case "Float" if(Std.is(data, Float)): FloatConverter.toString(data, options.delimiter);
				case "String" if(Std.is(data, String)): data;
				
				case _:	throw "DynamicObjectConverter.toDynamicObject: Invalid type '" 
								+ Type.typeof(data) + '\' ($convert) for field $fieldName';
			};

			Reflect.setField(output, fieldName, converted);
		}		
		
		return output;
	}
	
	public static function fromDynamic<T : DataClass>(cls : Class<T>, data : {}, ?delimiter : String) : T {
		if (delimiter == null) delimiter = Converter.delimiter;
		
		//trace("===== fromDynamicObject: " + Type.getClassName(cls));
		//trace(data);
		
		var columns = Meta.getFields(cls);
		var output = {};
		
		//trace(columns);
		
		for (fieldName in Reflect.fields(columns)) if(Reflect.hasField(data, fieldName)) {
			//trace('Converting field $fieldName: ');
			
			var convert = convertTo(fieldName, columns);
			if (convert == null) continue;
			
			// java requires explicit Dynamic here.
			var data : Dynamic = Reflect.field(data, fieldName);
			//trace('$data to $convert');
			
			var converted : Dynamic = data == null ? null : switch convert {
				case "String" if(Std.is(data, String)): data;

				case "Bool" if(Std.is(data, String)): StringConverter.toBool(data);
				case "Bool" if(Std.is(data, Bool)): data;

				case "Int" if(Std.is(data, String)): StringConverter.toInt(data, delimiter);
				case "Int" if(Std.is(data, Int)): data;

				case "Date" if(Std.is(data, String)): StringConverter.toDate(data);
				case "Date" if(Std.is(data, Date)): data;

				case "Float" if(Std.is(data, String)): StringConverter.toFloat(data, delimiter);
				case "Float" if(Std.is(data, Float)): data;
				
				case _:	throw "DynamicObjectConverter.fromDynamicObject: Invalid type '" 
								+ Type.typeof(data) + '\' ($convert) for field $fieldName';
			};
			
			//trace('Result: $converted');
			
			Reflect.setField(output, fieldName, converted);
		}

		return Type.createInstance(cls, [output]);		
	}
}

class ColumnConverter {
	public static function fromColumnData<T : DataClass>(cls : Class<T>, data : Iterable<String>, ?delimiter : String) : T {
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
}

class StringConverter
{
	public static function toBool(s : String) : Bool
		return !(~/^(?:false|no|0|)$/i.match(s.trim()));
		
	public static function toDate(s : String) : Date
		return Date.fromString(s.trim());
		
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
}
