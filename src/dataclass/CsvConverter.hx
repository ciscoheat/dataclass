package dataclass;

import dataclass.Converter.ValueConverter;
import haxe.DynamicAccess;
import dataclass.Converter;

using Lambda;
using StringTools;
using DateTools;

typedef CsvConverterOptions = {
	> ConverterOptions,
	?floatDelimiter : String,
	?boolValues : { tru: String, fals: String },
}

class CsvConverter extends Converter
{
	public static function fromCsv<T : DataClass>(cls : Class<T>, csv : Array<Array<String>>) : Array<T> {
		return current.fromCsvArray(cls, csv);
	}

	public static function toCsv<T : DataClass>(array : Array<T>) : Array<Array<String>> {
		return current.toCsvArray(array);
	}
	
	public static var current(default, default) : CsvConverter = new CsvConverter();
	
	///////////////////////////////////////////////////////////////////////////
	
	public function new(?options : CsvConverterOptions) {
		super(options);

		valueConverters.set('Int', new IntValueConverter());

		valueConverters.set('Date', new DateValueConverter(
			Reflect.hasField(options, 'dateFormat') ? options.dateFormat : "%Y-%m-%d %H:%M:%S"
		));

		valueConverters.set('Float', new FloatValueConverter(
			Reflect.hasField(options, 'floatDelimiter') ? options.floatDelimiter : "."
		));

		valueConverters.set('Bool', new BoolValueConverter(
			if (Reflect.hasField(options, 'boolValues')) 
				{ tru: options.boolValues.tru, fals: options.boolValues.fals }
			else
				{ tru: "1", fals: "0" }
		));
	}
	
	public function fromCsvArray<T : DataClass>(cls : Class<T>, csv : Array<Array<String>>) : Array<T> {
		var it = csv.iterator();
		if (!it.hasNext()) return [];
		
		var header = it.next();
		
		return [while (it.hasNext()) {
			var obj : DynamicAccess<String> = { };
			var values = it.next();
			
			for (i in 0...Std.int(Math.min(values.length, header.length)))
				obj.set(header[i], values[i]);
				
			this.toDataClass(cls, obj);
		}];
	}

	public function toCsvArray<T : DataClass>(cls : Array<T>) : Array<Array<String>> {
		if (cls.length == 0) return [];
		var header = Converter.Rtti.rttiData(Type.getClass(cls[0])).keys();
		var rows = cls.map(function(dataClass) {
			var converted = this.fromDataClass(dataClass);
			return header.map(function(field) return Std.string(converted.get(field)));
		});
		
		return [header].concat(rows);
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
