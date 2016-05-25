# DataClass

A convenient way to instantiate data classes with validation, default values, null checks, etc... Give your data a bit more class!

## How to use

```haxe
enum Color { Red; Blue; }

class Person implements dataclass.DataClass 
{
	public var id : Int;             // Required field (cannot be null)
	public var name : Null<String>;  // Null<T> allows null

	@validate(~/[\w-.]+@[\w-.]+/)    // Regexp validation (adding ^ and $ unless one of them exists)
	public var email(default, null) : String;  // Works with properties

	@validate(_.length > 2)   // Expression validation, "_" is replaced with the field
	public var city : String;

	public var active : Bool = true;         // Default value
	public var color = Blue;                 // Works with Enums too, even without type
	public var created : Date = Date.now();  // And statements
	
	var internal : String;            // non-public fields aren't included
	@exclude public var test : Bool;  // neither are fields marked with @exclude
	@include var test2 = true;        // but you can include private fields with @include
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
		// runtime validation:
		p = new Person({
			id: 1,
			email: "nope",
			city: "X"
		});

		// Setting an value that won't validate will also throw at runtime:
		p = new Person({
			id: 1,
			email: "test@example.com",
			city: "Punxsutawney"
		});
		p.city = "X"; // Will throw exception
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

Note especially that the parameter must be called `data`.

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

Previously, a class coulde be made immutable by marking it with `@immutable`. This has been deprecated, and the way to do it now is to use the [immutable](http://lib.haxe.org/p/immutable/) haxelib. Add it with `-lib immutable` and let your classes implement `Immutable` instead.

## Inheritance

If you let a DataClass extend another class, fields in the superclass will be regarded as DataClass fields, so you will need to supply them when creating the object. Example.

```haxe
class Parent {
	@validate(_ > 0) public var id : Int;
}

class Person extends Parent implements DataClass {
	public var name : String;
}
```

```haxe
// Creating a Person
var p = new Person({name: "Test"}); // Doesn't work, requires id
var p = new Person({id: 1, name: "Test"}); // Ok
```

Note that in general, the superclass should not implement `DataClass`, rather it should be considered an abstract class for generic data like primary keys in a database.

## Manual validation

All classes implementing `dataclass.DataClass` will get a static `validate` method that can be used to test if some input date will pass validation:

```haxe
class Main {
	static function main() {
		var errors : Array<String>;
		
		// Will return an empty array, meaning that all data passed validation
		errors = Person.validate({
			id: 1,
			email: "test@example.com",
			city: "Punxsutawney"
		});

		// This will return an array with two fields, ["email", "city"], since
		// the email field isn't a valid email according the the Person class,
		// and the city field is missing.
		errors = Person.validate({
			id: 2,
			email: "none"
		});
		
		// Easy to use afterwards
		for(field in errors) {
			// Set attributes on html fields that failed validation, for example
		}
	}
}
```

The `validate` method will never throw an exception, and can be used with anonymous objects. It's useful for validating web form data, more about that in the conversion section below.

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
		
		var test = CsvTest.fromColMetaData(input);
		
		trace(test.third); // true (converted to a Bool type of course)
	}
}
```

Or if you prefer to keep your classes clean:

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
		
		trace(test.third); // true
	}
}
```

If you have a whole table of data, usually represented as an array of arrays, use [array comprehension](http://haxe.org/manual/lf-array-comprehension.html) to convert it:

```haxe
using Lambda;

var columns = ["first", "second", "third"];
var rows = [
	["123", "2015-01-01", "yes"],
	["456", "2015-01-02", "no"]
];

var objects = [for(row in rows) CsvTest.fromColumnData(columns, row)];
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
		var test = o.toStringData({
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

### Converting and validating a html form in the browser

Assuming a simple data class and a form exists:
	
```haxe
class Test implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_ > 1000) public var int : Int;
}
```

```html
<form>
	<input type="text" name="date">
	<select name="int">
		<option>10</option>
		<option>100</option>
		<option selected>1001</option>
	</select>
	<input type="checkbox" name="str" value="abcde" checked>
	<input type="submit" name="submit" value="Submit"/>
</form>
```

```haxe
import js.Browser;
import dataclass.HtmlFormConverter;

class Main {
	static function main() {
		var form : HtmlFormConverter = Browser.document.querySelector('form');
		
		// Basic conversions
		form.toMap();
		form.toJson();
		form.toAnonymous();
		form.toQueryString();
		
		// Validation and DataClass conversion
		var errors = form.validate(Test);
		var test = form.toDataClass(Test);
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
