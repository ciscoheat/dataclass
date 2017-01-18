package dataclass;

import DataClass;
import haxe.DynamicAccess;

using Lambda;
using StringTools;
using DateTools;

typedef CsvConverterOptions = {
	?floatDelimiter : String,
	?boolValues : { tru: String, fals: String },
	?dateFormat : String
}

class CsvConverter extends JsonConverter
{
	public static function fromCsvArray<T : DataClass>(csv : Array<Array<String>>, cls : Class<T>) : Array<T> {
		var it = csv.iterator();
		if (!it.hasNext()) return [];
		
		var header = it.next();
		
		return [while (it.hasNext()) {
			var obj : DynamicAccess<String> = { };
			var values = it.next();
			
			for (i in 0...Std.int(Math.min(values.length, header.length)))
				obj.set(header[i], values[i]);
				
			current.toDataClass(cls, obj);
		}];
	}

	public static function toCsvArray<T : DataClass>(cls : Array<T>) : Array<Array<String>> {
		if (cls.length == 0) return [];
		var header = Converter.Rtti.rttiData(Type.getClass(cls[0])).keys();
		
		return [header].concat(cls.map(function(dataClass) {
			var converted = current.fromDataClass(dataClass);
			return header.map(function(field) return converted.get(field));
		}));
	}
	
	public static var current(default, default) : CsvConverter = new CsvConverter();
	
	///////////////////////////////////////////////////////////////////////////
		
	public function new(?options : CsvConverterOptions) {
		super();

		valueConverters.set('Int', new IntValueConverter());
		
		valueConverters.set('Bool', new BoolValueConverter(
			Reflect.hasField(options, 'boolValues') ? options.boolValues : { tru: "1", fals: "0" }
		));

		valueConverters.set('Float', new FloatValueConverter(
			Reflect.hasField(options, 'floatDelimiter') ? options.floatDelimiter : "."
		));

		valueConverters.set('Date', new DateValueConverter(
			Reflect.hasField(options, 'dateFormat') ? options.dateFormat : "%Y-%m-%d %H:%M:%S"
		));
	}
}

private class IntValueConverter
{
	public function new() { }

	public function input(input : String) : Int {
		return Std.parseInt(input);
	}
	
	public function output(input : Int) : String {
		return Std.string(input);
	}
}

private class BoolValueConverter
{
	var boolValues : { tru: String, fals: String };
	
	public function new(boolValues) {
		this.boolValues = boolValues;
	}

	public function input(input : String) : Bool {
		return input == boolValues.tru ? true : false;
	}
	
	public function output(input : Bool) : String {
		return input == true ? boolValues.tru : boolValues.fals;
	}
}

private class FloatValueConverter
{
	var separator : String;
	
	public function new(separator) {
		this.separator = separator;
	}

	public function input(input : String) : Float {
		return Std.parseFloat(input.replace(separator, "."));
	}
	
	public function output(input : Float) : String {
		return Std.string(input).replace(".", separator);
	}
}

private class DateValueConverter
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
