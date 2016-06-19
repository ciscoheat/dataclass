package dataclass;

#if macro
import haxe.macro.Expr;
using haxe.macro.ExprTools;
using Lambda;
#end

import haxe.DynamicAccess;
import haxe.macro.Context;
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

	/**
	 * Creates a DataClass from a series of in-scope variables.
	 */
	macro public static function createFromVars<T : DataClass>(cls : ExprOf<Class<T>>, vars : Array<Expr>) {
		
		var assignments = {expr: EObjectDecl([for (v in vars) switch v {
			case macro $a.$b: {field: b, expr: v};
			case _: switch v.expr {
				case EConst(CIdent(s)): {field: s, expr: v };
				case _: Context.error('Invalid assignment, can only be "var" or "obj.field".', v.pos);
			}
		}]), pos: Context.currentPos() };
		
		function error() return Context.error("Invalid Class type: " + cls.toString(), cls.pos);
		
		// cls will be "this" if used as an extension, so the real type must be extracted
		var classType = switch Context.typeof(cls) {
			case TType(t, params): 
				// The real type is found within Class<...>
				var type = ~/^Class<(.*)>$/;
				if (!type.match(t.get().name)) error();
				
				var name = type.matched(1).split(".");
				var module = t.get().module.split(".");
				//trace("======="); trace(module); trace(name);

				// And now some crazy stuff...				
				
				var topClassInPackage = name.length > 1 && module.slice(0, -1).join("") == name.slice(0, -1).join("");
				
				{ 
					sub: topClassInPackage ? name[name.length-1] : null,
					params: null,
					pack: module.slice(0, -1),
					name: topClassInPackage ? module[module.length-1] : name[name.length-1]
				};
				
			case _: 
				error();
		}
		
		return macro new $classType($assignments);
	}
	
	/**
	 * Assigns a series of in-scope variables to the fields with the same name.
	 */
	macro public static function assignFromVars(o : ExprOf<DataClass>, vars : Array<Expr>) {
		var assignments = [for (v in vars) switch v {
			case macro $a.$b: macro $o.$b = $v;			
			case _: switch v.expr {
				case EConst(CIdent(s)): macro $o.$s = $v;
				case _: Context.error('Invalid assignment, can only be "var" or "obj.field".', v.pos);
			}
		}];

		return { expr: EBlock(assignments), pos: Context.currentPos() };
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
	public static function toAnonymousStructure<T : DataClass>(from : DataClass) : Dynamic {
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
		var columns = Meta.getFields(cls);
		var output = { };

		for (fieldName in Reflect.fields(columns)) {
			var convert = convertMetadata("convertTo", fieldName, columns);
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
	public static function fromDynamic<T : DataClass>(cls : Class<T>, data : {}, ?delimiter : String) : T {
		return Type.createInstance(cls, [toCorrectTypes(cls, data, delimiter)]);
	}

	/**
	 * Converts a Dynamic object to another Dynamic object with correct types for a specified DataClass.
	 */
	public static function toCorrectTypes<T : DataClass>(cls : Class<T>, data : {}, ?delimiter : String) : Dynamic {
		if (delimiter == null) delimiter = Converter.delimiter;
		
		//trace("===== fromDynamicObject: " + Type.getClassName(cls));
		//trace(data);
		
		var columns = Meta.getFields(cls);
		var output = {};
		
		//trace(columns);
		
		for (fieldName in Reflect.fields(columns)) if(Reflect.hasField(data, fieldName)) {
			//trace('Converting field $fieldName: ');
			
			var convert = convertMetadata("convertFrom", fieldName, columns);
			if (convert == null) continue;
			
			// java requires explicit Dynamic here.
			var data : Dynamic = Reflect.field(data, fieldName);
			//trace('$data to $convert');
			
			var converted : Dynamic = data == null ? null : switch convert {
				case "String": Std.string(data);

				case "Bool" if(Std.is(data, String)): StringConverter.toBool(data);
				case "Bool" if(Std.is(data, Bool)):   data;

				case "Int" if(Std.is(data, String)): StringConverter.toInt(data, delimiter);
				case "Int" if(Std.is(data, Int)):    data;

				case "Date" if(Std.is(data, String)): StringConverter.toDate(data);
				case "Date" if(Std.is(data, Float)):  FloatConverter.toDate(data);
				case "Date" if(Std.is(data, Int)):    IntConverter.toDate(data);
				case "Date" if(Std.is(data, Date)):   data;

				case "Float" if(Std.is(data, String)): StringConverter.toFloat(data, delimiter);
				case "Float" if(Std.is(data, Float)):  data;
				
				case _:	throw "Invalid type '" + Type.typeof(data) + '\' ($convert) for field $fieldName';
			};
			
			//trace('Result: $converted');
			
			Reflect.setField(output, fieldName, converted);
		}

		return output;
	}
	
	///////////////////////////////////////////////////////////////////////////
	
	public static var supportedTypes(default, null) = ["Bool", "Date", "Int", "Float", "String"];

	static function convertMetadata(metaDataName, fieldName, columns) {
		var field = Reflect.field(columns, fieldName);
		return Reflect.hasField(field, metaDataName) ? Reflect.field(field, metaDataName)[0] : null;
	}	
}

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
