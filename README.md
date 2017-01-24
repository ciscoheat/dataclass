# DataClass

A convenient way to instantiate your domain objects, DTO's, web forms, and other data structures with validation, default values, null checks, etc... Give your data a bit more class!

## How to use

```haxe
enum Color { Red; Blue; }

class Person implements DataClass 
{
	public var id : Int;             // Required field (cannot be null)
	public var name : Null<String>;  // Null<T> allows null

	@validate(~/[\w-.]+@[\w-.]+/)    // Regexp validation (testing whole string unless ^ or $ exists in regexp)
	public var email(default, null) : String;  // Works with properties

	@validate(_.length > 2)   // Expression validation, "_" is replaced with the field
	public var city : String;

	public var active : Bool = true;         // Default value
	public var color = Blue;                 // Works for Enums without constructors
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

		// Setting an value that won't validate 
		// will throw at runtime. 
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
class Custom implements DataClass {
	public function new(data) { // One parameter is required
		// Your code here...
	}
}
```

At the top of this constructor, all the assignments will be inserted. So when running it will look similar to this:

```haxe
class Custom implements DataClass {
	public var id : Int;
	
	public function new(data) {
		this.id = data.id;
		// Your code here...
	}
}
```

## Immutability

A class can be made immutable from the outside by marking it with `@immutable`, which will simply change all `var` to `var(default, null)`. Quite useful when doing event sourcing and using event stores, for example.

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

The superclass should not implement `DataClass`, rather it should be considered an abstract class for data like primary keys in a database.

## Manual validation

All classes implementing `DataClass` will get a static `validate` method that can be used to test if some input will pass validation:

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

The `validate` method won't throw an exception, and can be used with anonymous objects. If you don't want the method on a specific class, you can skip it by adding a `@noValidator` metadata.

## Conversion utilities

### JSON

Converting to and from JSON is quite useful, especially with the popularity of NoSQL databases. DataClass has a nested structure JSON converter available.

By adding `using dataclass.JsonConverter;` you'll get some useful extensions on the DataClass types:

```haxe
using dataclass.JsonConverter;

enum Color { Red; Blue; }

class Test implements DataClass {
	public var first : Int;
	public var second : Date;
	public var third : Color;
	// Nested structures must be a DataClass
	public var anotherTest : Null<Test>;
}

class Main {
	static function main() {
		var json = {
			first: 123, 
			second: "2017-01-19T12:00:00Z", 
			third: Red,
			anotherTest: {
				first: 1, 
				second: "2000-10-10T01.01.01Z", 
				third: Blue
			}
		};
		
		var test = Test.fromJson(json);
		trace(test.anotherTest.second.getFullYear()); // 2000

		test.third = Blue;
		var newJson = test.toJson();
		trace(newJson.get("third")); // "Blue"
	}
}
```

The extension methods are handled by `dataclass.JsonConverter.current`, which you can reassign if you want different settings. When instantiating, you have two options:
	
- `dateFormat`: Sets the converted string format for `Date`. Default is ISO 8601 for UTC: `yyyy-mm-ddThh:mm:ssZ` **NOTE:** only Zulu time is supported for this format, because of platform differences.
- `circularReferences`: An Enum with three values. The default, `ThrowException`, throws an exception when it detects a circular reference. `SetToNull`, sets those circular references to `null` instead. `TrackReferences` keeps track of the references, stores them in JSON and restores them when converted back, at a small storage and time penalty.

Of course, you can instantiate your own `dataclass.JsonConverter` if you don't want to use the extension methods.

### CSV

Another widely used format is CSV. DataClass doesn't parse it, there are many CSV parsers out there, but it gladly converts the resulting CSV structure into DataClass objects.

First, make sure your data is in the type `Array<Array<String>>`, where the header row of the inner array contains field names corresponding to the DataClass object, and the rest is the actual row data.

Then add `using dataclass.CsvConverter`. For example:

```haxe
using dataclass.CsvConverter;

class Test implements DataClass {
	public var first : Int;
	public var second : Date;
	public var third : Bool;
}

class Main {
	static function main() {
		// Parsed data, organized into Array<Array<String>>
		var csv = [
			["first", "second", "third"],
			["123", "2015-01-01", "1"],
			["456", "2017-01-19", "0"]
		];
		
		var data = Test.fromCsv(csv);
		
		trace(data[0].third); // true
		trace(data[1].second.getFullYear()); // 2017
		
		var newCsv = data.toCsv();
	}
}
```

Here are the settings available, if you want to set your own CsvConverter:
	
- `delimiter` allows you to specify the delimiter for `Float` conversion. The default is `.` (period).
- `boolValues` sets the converted string values for `true` and `false`. Default is "1" and "0". Any value not equal to the string value of true is considered false.
- `dateFormat` sets the converted format for `Date` values. **NOTE:** Unlike JSON, the default format for CSV is `yyyy-mm-dd hh:mm:ss`.

### Html

Assuming a simple data class and a form exists:
	
```haxe
class Test implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_ > 1000) public var int : Array<Int>;
	public var ok : Bool;
}
```

```html
<form>
	<input type="text" name="date">
	<select multiple name="int">
		<option>10</option>
		<option>100</option>
		<option selected>1001</option>
	</select>
	<input type="hidden" name="ok" value="0">
	<input type="checkbox" name="ok" value="1" checked>
	<input type="submit" name="submit" value="Submit"/>
</form>
```

You can then convert the form to a `Test` object using a `HtmlFormConverter`, which takes the same options as the `CsvConverter`.

```haxe
import js.Browser;
import dataclass.HtmlFormConverter;

class Main {
	static function main() {
		var form = new HtmlFormConverter(Browser.document.querySelector('form'));
		
		// String values of the form, except select-multiple which is Array<String>
		form.toAnonymousStructure();
		
		// Serializes the form to a querystring
		form.toQueryString();
		
		// Validation and DataClass conversion		
		var errors = form.validate(Test);
		
		if(errors.length == 0)
			var test = form.toDataClass(Test);
	}
}
```

## Built-in converters

To keep the conversion efficient, not every type can be converted to and from the above formats. There is built-in support for the following:
	
- Primitive types: `Int`, `Bool`, `Float`, `String`, `Enum` (with no constructors)
- Composite types: `Array<T>`, `StringMap<T>`, `IntMap<T>`

Where `T` is one of the primitive types, or a class implementing `DataClass`.

All other DataClass fields must be one of the above types. If you need more, you can create your own value converters:

## Custom value converters

You can add custom converters for any type, so your data can be conveniently converted. An `IntValueConverter` for the CSV parser is a simple example:

```haxe
// For some reason we want to invert the sign of the integers.
class IntValueConverter
{
	public function new() {}

	// For CSV, the input is String.
	public function input(input : String) : Int {
		return -Std.parseInt(input);
	}
	
	public function output(input : Int) : String {
		return Std.string(-input);
	}
}

class Main {
	static function main() {
		var converter = new CsvConverter();
		converter.valueConverters.set('Int', new IntValueConverter());

		// ... ready to use!
	}
}
```

For the moment, type parameters cannot be used in custom value converters.

## Custom exceptions

When a validation fails, a `String` is thrown, but you can define `-D dataclass-throw=your.CustomException`, and all failed validation will be thrown as 

```haxe
throw new your.CustomException(errorMessage : String, thisRef : Dynamic, failedValue : Dynamic);
```

As a convenience, you can also define `-D dataclass-throw-js-error` to throw `js.Error(errorMessage : String)`.

### Specific library support

DataClass plays very nicely together with [HaxeContracts](https://github.com/ciscoheat/HaxeContracts): If the class implements `haxecontracts.HaxeContracts`, a `haxecontracts.ContractException` will be thrown instead of a `String` when a validation or null-check fails.

## Installation

`haxelib install dataclass`, then put `-lib dataclass` in your `.hxml` file.

## Connection to DCI

Simple domain objects are used in the Data part of the [DCI architecture](https://en.wikipedia.org/wiki/Data,_context_and_interaction). They represent what the system *is*, and have no connections to other objects. They play Roles in DCI Contexts, where they become parts of Interactions between other objects, describing what the system *does* based on a user mental model. The [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository has a thorough tutorial of the DCI paradigm in Haxe if you're interested.

[![Build Status](https://travis-ci.org/ciscoheat/dataclass.svg?branch=master)](https://travis-ci.org/ciscoheat/dataclass)
