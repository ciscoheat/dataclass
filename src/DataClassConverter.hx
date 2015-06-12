
import haxe.rtti.Meta;

using StringTools;
using DataClassConverter;

class DataClassConverter
{
	///// Default configuration /////	
	public static var delimiter = ".";
	public static var boolValues = { tru: "1", fals: "0" };
	public static var dateFormat = "%Y-%m-%d %H:%M:%S";	

	public static function toBool(s : String)
		return !(~/^(?:false|no|0|)$/i.match(s.trim()));
		
	public static function toDate(s : String)
		return Date.fromString(s.trim());
		
	public static function toInt(s : String, ?delimiter : String) {
		if (delimiter == null) delimiter = DataClassConverter.delimiter;
		
		var str = s.replace(delimiter, ".");
		return Std.parseInt(str);
	}

	public static function toFloat(s : String, ?delimiter : String) {
		if (delimiter == null) delimiter = DataClassConverter.delimiter;
		
		var delimPos = s.lastIndexOf(delimiter);			
		var clean = function(s) return ~/\D/g.replace(s, "");
		
		return Std.parseFloat(delimPos == -1
			? clean(s)
			: clean(s.substr(0, delimPos)) + "." + clean(s.substr(delimPos))
		);
	}
}

class StringObjectConverter {
	public static var supportedTypes(default, null) = ["Bool", "Date", "Int", "Float", "String"];
	
	public static function fromStringObject<T : DataClass>(cls : Class<T>, data : {}) : T {

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
			
			var converted : Dynamic = switch convert {
				case "String" if(Std.is(fieldData, String)): fieldData;
				case "Bool" if(Std.is(fieldData, String) || Std.is(fieldData, Bool)): fieldData.toBool();
				case "Int" if(Std.is(fieldData, String) || Std.is(fieldData, Int)): fieldData.toInt();
				case "Date" if(Std.is(fieldData, String) || Std.is(fieldData, Date)): fieldData.toDate();
				case "Float" if(Std.is(fieldData, String) || Std.is(fieldData, Float)): fieldData.toFloat();
				case _:	throw "Invalid type for StringObjectConverter.fromStringObject on field " + fieldName;
			};
			
			Reflect.setField(output, fieldName, converted);
		}

		return Type.createInstance(cls, [output]);		
	}
}

class ColumnConverter {
	public static function fromColumnData<T : DataClass>(cls : Class<T>, data : Iterable<String>) : T {
		var columns = Meta.getFields(cls);		
		var input = Lambda.array(data);
		var output = {};
		
		for (fieldName in Reflect.fields(columns)) {
			var field = Reflect.field(columns, fieldName);
			var col = Reflect.field(field, "col")[0];
			Reflect.setField(output, fieldName, input[col - 1]);
		}
		
		return StringObjectConverter.fromStringObject(cls, output);
	}
}

class BoolConverter {
	public static function toString(b : Bool, ?boolValues : {tru: String, fals: String}) {
		if (boolValues == null) boolValues = DataClassConverter.boolValues;
		return b ? boolValues.tru : boolValues.fals;
	}
}

class IntConverter {
	public static function toString(i : Int)
		return Std.string(i);
}

class DateConverter {
	public static function toStringFormat(d : Date, ?format : String) {
		if (format == null) format = DataClassConverter.dateFormat;
		return DateTools.format(d, format);
	}
}

class FloatConverter {
	public static function toString(f : Float, ?delimiter : String) {
		if (delimiter == null) delimiter = DataClassConverter.delimiter;
		return Std.string(f).replace(".", delimiter);
	}
}
