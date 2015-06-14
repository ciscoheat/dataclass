# DataClass

A more convenient way to instantiate data classes.

```haxe
enum Color { Red; Blue; }

class Person implements dataclass.DataClass {
	public var id : Int 			 // Required
	public var name : Null<String>	 // Optional

	@validate(~/[\w-.]+@[\w-.]+/)	 			// Regexp validation, adding ^ and $ if one of them doesn't exist
	public var email(default, null) : String	// Works with properties

	@validate(_.length > 2)			 // Expression validation
	public var city : String		 // "_" is replaced with the field

	public var active : Bool = true; // Default value
	public var color : Color = Blue; // Works with Enums too
}

class Main {
	static function main() {
		var p : Person;
		
		// A Person can	now be created like this:
		p = new Person({
			id: 1,
			email: "test@example.com",
			city: "Punxsutawney"
		});

		// This will throw an exception because 
		// the required id field is missing:
		p = new Person({
			name: "Test",
			email: "test@example.com",
			city: "Punxsutawney"
		});
		
		// This will throw an exception because of 
		// null checks and validation:
		p = new Person({
			id: null,
			email: "nope",
			city: "X"
		});
	}
}
```

## Constructors

A constructor will be automatically generated, but if you want to add your own it should be in this format:

```haxe
class Custom implements dataclass.DataClass {
	public function new(data) {
		// Code here...
	}
}
```

At the top of this constructor, all the assignments will be inserted. So when running it will look similar to this:

```haxe
class Custom implements dataclass.DataClass {
	public var id : Int;
	
	public function new(data) {
		this.id = data.id;
		// Code here...
	}
}
```

## Conversion utilities

DataClass have some ways to simplify the tedious data conversion process when you get input data from for example a CSV file or JSON data containing only strings, and they should be mapped to a Haxe object.

If you add `using dataclass.Converter;` to any module you'll get some useful extensions on the supported types. For `String`:
	
```
.toBool()
.toInt()
.toDate()
.toFloat()
```

And the opposite for each type: `.toString()` (date has `.toStringFormat()`).

These methods have some intelligence that handles when for example the input isn't whitespace trimmed or contains currency symbols. You should be able to pass most spreadsheet data into it without problem. [Post an issue](https://github.com/ciscoheat/dataclass/issues) if not.

There are some settings for the conversion process in `dataclass.Converter`:
	
- `Converter.delimiter` allows you to specify the delimiter for `Float`.
- `Converter.boolValues` sets the converted string values for `true` and `false`.
- `Converter.dateFormat` sets the converted string `Date` value.

You can also set the relevant values directly when calling the conversion methods if you prefer that.

That's for simple values, but what about the CSV or JSON data? This is where it gets fun. For any class implementing `DataClass`, you now have some extensions for the class itself:
	
```haxe
import dataclass.DataClass;
using dataclass.Converter;

class CsvTest implements DataClass {
	// In the DataClass, specify the positions for each column (starts with 1, not 0)
	@col(1) public var first : Int;
	@col(2) public var second : Date;
	@col(3) public var third : Bool;
}

class Main {
	static function main() {
		// A row parsed from a CSV file:
		var input = ["123", "2015-01-01", "yes"];
		
		var test = CsvTest.fromColumnData(input);
		
		trace(test.third); // true (converted to a Bool type of course)
	}
}
```

```haxe
import dataclass.DataClass;
using dataclass.Converter;

class JsonTest implements DataClass {
	public var first : Int;
	public var second : Date;
	public var third : Bool;
}

class Main {
	static function main() {
		// Parsed JSON data
		var input = haxe.Json.parse('{"first":123, "second":"2015-01-01", "third":"", "extra":"will not be added"}');
		
		var test = JsonTest.fromDynamicObject(input);
		
		trace(test.first); // 123
		trace(test.second.getFullYear()); // 2015
		trace(test.third); // false
	}
}
```

These class-level conversion methods only works with the supported types, currently `String, Int, Float, Date` and `Bool`. Other types, or extra fields on the input will be ignored. If you have other fields you can set them up later in the normal way:

```haxe
var input = haxe.Json.parse('{"first":123, "second":"2015-01-01", "third":"", "other":[1,2,3]}');
var test = JsonTest.fromDynamicObject(input);
test.other = input.other;
```	

**Note:** The above methods protects you from most runtime surprises, but if you have a custom constructor it must take the data object as first parameter, and have all other parameters optional. Also due to some type checking they take a performance hit, but it should be negligible in most cases. As usual, don't optimize unless you have obvious performance problems.

## Installation

`haxelib install dataclass` then put `-lib dataclass` in your `.hxml` file.

## Todo

- [x] Allow get/set properties
- [x] [Mithril](https://github.com/ciscoheat/mithril-hx) support for `M.prop`
- [ ] [HaxeContracts](https://github.com/ciscoheat/HaxeContracts) option for exceptions
- [ ] CI testing with [Travis](http://docs.travis-ci.com/user/languages/haxe/)
- [ ] Initialize with a default value without type
- [ ] [Mongoose](http://mongoosejs.com/) support for Node.js

## Connection to DCI

Simple data objects are the very foundation of the [DCI architecture](https://en.wikipedia.org/wiki/Data,_context_and_interaction). They represent what the system *is*, and have no connections to other objects. They play Roles in DCI Contexts, where they become parts of Interactions between other objects, describing what the system *does* based on a user mental model. The [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository has a thorough tutorial of the DCI paradigm in Haxe if you're interested.
