package dataclass;

import haxe.rtti.Meta;

using StringTools;
using Converter.StringConverter;

class Converter
{
	///// Default configuration /////	
	public static var delimiter = ".";
	public static var boolValues = { tru: "1", fals: "0" };
	public static var dateFormat = "%Y-%m-%d %H:%M:%S";	
}

class DynamicObjectConverter {
	public static var supportedTypes(default, null) = ["Bool", "Date", "Int", "Float", "String"];
	
	public static function fromDynamicObject<T : DataClass>(cls : Class<T>, data : {}, ?delimiter : String) : T {
		if (delimiter == null) delimiter = Converter.delimiter;
		
		var columns = Meta.getFields(cls);
		var output = {};
		
		function convertTo(fieldName) {
			var field = Reflect.field(columns, fieldName);
			return Reflect.hasField(field, "convertTo") ? Reflect.field(field, "convertTo")[0] : null;
		}
		
		for (fieldName in Reflect.fields(data)) {
			var convert = convertTo(fieldName);
			if (convert == null) continue;
			
			var fieldData : String = Reflect.field(data, fieldName);
			//trace('Converting $fieldData to $convert');
			
			var converted : Dynamic = switch convert {
				case "String" if(Std.is(fieldData, String)): fieldData;

				case "Bool" if(Std.is(fieldData, String)): fieldData.toBool();
				case "Bool" if(Std.is(fieldData, Bool)): fieldData;

				case "Int" if(Std.is(fieldData, String)): fieldData.toInt();
				case "Int" if(Std.is(fieldData, Int)): fieldData;

				case "Date" if(Std.is(fieldData, String)): fieldData.toDate();
				case "Date" if(Std.is(fieldData, Date)): fieldData;

				case "Float" if(Std.is(fieldData, String)): fieldData.toFloat();
				case "Float" if(Std.is(fieldData, Float)): fieldData;
				
				case _:	throw "DynamicObjectConverter: Invalid type '" + Type.typeof(fieldData) + "' for field " + fieldName;
			};
			
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
			var col = Reflect.field(field, "col")[0];
			Reflect.setField(output, fieldName, input[col - 1]);
		}
		
		return DynamicObjectConverter.fromDynamicObject(cls, output, delimiter);
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
		return Std.parseInt(s.replace(delimiter, "."));
	}

	public static function toFloat(s : String, ?delimiter : String) : Float {
		if (delimiter == null) delimiter = Converter.delimiter;
		
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
