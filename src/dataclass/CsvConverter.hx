package dataclass;

import dataclass.Converter.ValueConverter;
import haxe.DynamicAccess;
import dataclass.Converter;
import dataclass.Converter.config;

using Lambda;
using StringTools;
using DateTools;

class CsvConverter extends dataclass.Converter
{
	public static function fromCsv<T : DataClass>(cls : Class<T>, csv : Array<Array<String>>) : Array<T> {
		return current.fromCsvArray(cls, csv);
	}

	public static function toCsv<T : DataClass>(array : Array<T>) : Array<Array<String>> {
		return current.toCsvArray(array);
	}
	
	public static var current(default, default) : CsvConverter = new CsvConverter();
	
	///////////////////////////////////////////////////////////////////////////
	
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
