# DataClass

A convenient way to instantiate data classes with validation, default values, null checks, etc... Give your data a bit more class!

## How to use

```haxe
enum Color { Red; Blue; }

class Person implements dataclass.DataClass {
	public var id : Int;             // Required field (cannot be null)
	public var name : Null<String>;  // Null<T> allows null

	@validate(~/[\w-.]+@[\w-.]+/)              // Regexp validation, auto-adding ^ and $ unless one of them exists
	public var email(default, null) : String;  // Works with properties

	@validate(_.length > 2)   // Expression validation, "_" is replaced with the field
	public var city : String;

	public var active : Bool = true;         // Default value
	public var color : Color = Blue;         // Works with Enums too
	public var created : Date = Date.now();  // And statements
	
	var internal : String;           // non-public vars aren't included
	@ignore public var test : Bool;  // neither are fields marked with @ignore
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

		// This will not compile because 
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
		// Your code here...
	}
}
```

Note specifically that the first parameter must be called `data`. 

At the top of this constructor, all the assignments will be inserted. So when running it will look similar to this:

```haxe
class Custom implements dataclass.DataClass {
	public var id : Int;
	
	public function new(data) {
		this.id = data.id;
		// Your code here...
	}
}
```

## Immutability

A class can be made immutable, or at least shallow immutable (meaning that Arrays and such can still be modified), by marking it with `@immutable`. This will change all `public var` fields to `public var(default, null)`, and prevent internal changes to those. 

An immutable class is a good candidate for [Event Sourcing](http://docs.geteventstore.com/introduction/event-sourcing-basics/), and some proponents of [DCI](https://github.com/ciscoheat/haxedci-example) suggests that the data objects of DCI (simple objects with no connections to others) should always be immutable.

## Conversion utilities

By adding `using dataclass.Converter;` you'll get some useful extensions on the supported types.

### Single value conversions

```
var s = "A string";

s.toBool()
s.toInt()
s.toDate()
s.toFloat()
```

And the opposite for each type: `.toString()` (date has `.toStringFormat()`).

These methods have some intelligence that handles when for example the input isn't whitespace trimmed or contains currency symbols. You should be able to pass most spreadsheet data into them without problem. [Post an issue](https://github.com/ciscoheat/dataclass/issues) if not.

### Settings

There are some settings for the conversion process in `dataclass.Converter`:
	
- `Converter.delimiter` allows you to specify the delimiter for `Float`. The default is `.`, but can also be set to a blank string for auto-detecting period or comma.
- `Converter.boolValues` sets the converted string values for `true` and `false`.
- `Converter.dateFormat` sets the converted string `Date` value.

You can also set the relevant values directly when calling the conversion methods if you prefer that.

## Dynamic conversions

DataClass has some ways to simplify the tedious data conversion process when you get input data from for example a CSV file or JSON data containing only strings, and they should be mapped to a Haxe object.

### Converting CSV data

```haxe
using dataclass.Converter;

class CsvTest implements dataclass.DataClass {
	// In the DataClass, specify the positions for each column (starts with 1, not 0)
	@col(1) public var first : Int;
	@col(2) public var second : Date;
	@col(3) public var third : Bool;
}

class Main {
	static function main() {
		// A row parsed from a CSV file:
		var input = ["123", "2015-01-01", "yes"];
		
		var test = CsvTest.fromClassData(input);
		
		trace(test.third); // true (converted to a Bool type of course)
	}
}
```

Or if you prefer to keep your classes clean (and risk string typos):

```haxe
using dataclass.Converter;

class CsvTest implements dataclass.DataClass {
	public var first : Int;
	public var second : Date;
	public var third : Bool;
}

class Main {
	static function main() {
		var columns = ["first", "second", "third"];
		var input = ["123", "2015-01-01", "yes"];
		
		var test = CsvTest.fromColumnData(columns, input);
		
		trace(test.third);
	}
}
```

If you have a whole table of data, usually represented as an array of arrays, use `Lambda.map` to convert it:

```haxe
using Lambda;

var columns = ["first", "second", "third"];
var rows = [
	["123", "2015-01-01", "yes"],
	["456", "2015-01-02", "no"]
];

var objects = rows.map(function(row) return CsvTest.fromColumnData(columns, row));
```

### Converting JSON data

```haxe
using dataclass.Converter;

class JsonTest implements dataclass.DataClass {
	public var first : Int;
	public var second : Date;
	public var third : Bool;
}

class Main {
	static function main() {
		// Parsed JSON data
		var input = haxe.Json.parse('{"first":123, "second":"2015-01-01", "third":"", "extra":"will not be added"}');
		
		var test = JsonTest.fromDynamic(input);
		
		trace(test.first); // 123
		trace(test.second.getFullYear()); // 2015
		trace(test.third); // false
	}
}
```

### Converting a DataClass to Dynamic<String>

```haxe
using dataclass.Converter;

class JsonTest implements dataclass.DataClass {
	public var first : Int;
	public var second : Date;
	public var third : Bool;
}

class Main {
	static function main() {
		var o = new JsonTest({first: 123, second: Date.now(), third: true});
		
		// Demonstrating the converter settings:
		var test = o.toDynamic({
			delimiter: ",",
			dateFormat: "%d/%m/%y",
			boolValues: { tru: "YES", fals: "NO" } // (No typo, it's to avoid the reserved words)
		});
		
		trace(test.first); // "123"
		trace(test.second); // "22/06/15"
		trace(test.third); // "YES"
	}
}
```	

These object-level conversions only works with the supported types, currently `String, Int, Float, Date` and `Bool`. Other types, or extra fields on the input will be ignored for type-safety reasons. If you have other fields you can set them up later in the normal way:

```haxe
var input = haxe.Json.parse('{"first":123, "second":"2015-01-01", "third":"", "other":[1,2,3]}');
var test = JsonTest.fromDynamic(input);
test.other = input.other;
```	

**Notes about the dynamic conversion**

1. If you're using the `-dce full` compiler directive, make sure you add a `@:keep` metadata to the classes you're going to use with the dynamic conversion methods.
1. If the class has a constructor it must take the data object as first parameter, and have all other parameters optional. 
1. Due to the runtime type checking there is a performance hit, but it should be negligible in most cases. As usual, don't optimize unless you have obvious performance problems.

## Specific library support

DataClass plays very nicely together with [HaxeContracts](https://github.com/ciscoheat/HaxeContracts): If the class implements `haxecontracts.HaxeContracts`, a `haxecontracts.ContractException` will be thrown instead of a `String` when a validation or null-check fails.

## Installation

`haxelib install dataclass` then put `-lib dataclass` in your `.hxml` file.

## Connection to DCI

Simple data objects are the very foundation of the [DCI architecture](https://en.wikipedia.org/wiki/Data,_context_and_interaction). They represent what the system *is*, and have no connections to other objects. They play Roles in DCI Contexts, where they become parts of Interactions between other objects, describing what the system *does* based on a user mental model. The [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository has a thorough tutorial of the DCI paradigm in Haxe if you're interested.

[![Build Status](https://travis-ci.org/ciscoheat/dataclass.svg?branch=master)](https://travis-ci.org/ciscoheat/dataclass)
