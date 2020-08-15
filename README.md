# DataClass

A convenient way to instantiate your data objects with validation, default values, null checks, etc... Give your data a bit more class!

The documentation for the supplemental `DataMap` is located [in the wiki](https://github.com/ciscoheat/dataclass/wiki/DataMap).

## How to use

```haxe
import haxe.ds.Option;

enum Color { Red; Blue; }

// Add @:publicFields to make all fields public
@:publicFields class Person implements DataClass 
{
	///// Basic usage /////

	final id : Int;             // Required field (cannot be null)
	final name : Null<String>;  // Null<T> allows null

	///// Validation /////

	@:validate(_.length >= 2) // Expression validation, "_" is replaced with the field
	final city : String;

	@:validate(~/[\w-.]+@[\w-.]+/) // Regexp validation
	final email : String;

	///// Default values /////

	final color : Color = Blue;
	final created : Date = Date.now(); // Works also for statements

	///// Null safety /////

	final avoidNull : Option<String>; // Option is automatically set to None instead of null.

	@:validate(_ == "ok") // Validation for Option is tested for the wrapped value
	final defaultOption : Option<String> = "ok"; // Will become Some("ok")

	///// Properties /////

	var isBlue(get, never) : Bool; // Only get/never properties are allowed.
	function get_isBlue() return color.match(Blue);
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
	}
}
```

## Null safety notes

If you want to avoid `Null<T>` completely in DataClass you can use `haxe.ds.Option<T>`, but be sure to test for `null` in validators. This also applies when validating `Option<T>`, where a `None` value will be `null` in a validator! Example:

```haxe
// Same validation as for Null<String>
@:validate(_ == null || _.length > 1)
final name : Option<String>;
```

To avoid the null check completely, specify a default value for the field, as in the example below. Just remember that the default value will **not** be tested against any validators (it creates issues with inheritance and error handling).

```haxe
@:validate(_.length > 1)
final name : Option<String> = "No name";
```

## Customizing the auto-generated constructor

A constructor will be automatically generated, but if you want to add your own it should be in the following format. For this purpose you can also use `@:exclude` on fields that you want to set in the constructor yourself.

```haxe
class Custom implements DataClass {
	public final id : Int;
	@:exclude public final idStr : String;
	// ...

	// A parameter called 'data' is required
	public function new(data) { 
		// [Generated code inserted here]

		// Your code here:
		this.idStr = Std.string(this.id);
	}
}
```

Validating in the constructor is useful when you have validation rules spanning multiple fields.

## Inheritance

If you let a DataClass extend another class, fields in the superclass will be regarded as DataClass fields, so you will need to supply them when creating the object. Example.

```haxe
class Parent implements DataClass {
	@:validate(_ > 0)
	public final id : Int;
}

class Person extends Parent {
	public final name : String;
}
```

```haxe
// Creating a Person
final p = new Person({name: "Test"}); // Doesn't work, requires id
final p = new Person({id: 1, name: "Test"}); // Ok
```

## Interfaces

You can add validators to an interface, they will be used in the implementing DataClass.

```haxe
interface IChapter extends DataClass // extending is optional, but convenient
{
	@:validate(_.length > 0)
	public final info : String;
}
```

## Validation

All classes implementing `DataClass` will get a static `validate` method that can be used to test if some input data will pass validation:

```haxe
class Main {
	static function main() {
		var errors : haxe.ds.Option<dataclass.DataClassErrors>;
		
		// Will return Option.None, meaning that all data passed validation
		errors = Person.validate({
			id: 1,
			email: "test@example.com",
			city: "Punxsutawney"
		});

		// This will return Option.Some(errors), where errors is a Map<String, Option<Any>>, in this case
		// ["email" => Some("no email"), "city" => None] (where None represents a null value)
		errors = Person.validate({
			id: 2,
			email: "no email"
		});
	}
}
```

The `validate` method requires a complete input set, which may not be ideal when checking a single value like a html input field. Therefore all fields with validators will generate a static `validateFieldName(testValue) : Bool` method as well.

## Updating the object

Since all fields must be `final`, changing the DataClass object isn't possible, but a static `copy` method is available which you can use to create new objects of the same type in a simple manner:

```haxe
final p = new Person({id: 1, name: "Test"});
final p2 = Person.copy(p, {id: 2});
```

Or even fancier, add a `using` statement:

```haxe
using Person;

final p = new Person({id: 1, name: "Test"});
final p2 = p.copy({id: 2});
```

## Updating and validating for the web

When handling browser form input, it could be tempting to make a `DataClass` for the form, but for every keystroke or click the model will mutate, so it's more convenient to make a simpler data structure for the form:

```haxe
@:publicFields @:structInit private class Form {
    var firstName : String;
    var lastName : String;
    var email : String;
}
```

For validation, a `DataClass` can be used. Here's how it would look like in [Mithril](https://github.com/ciscoheat/mithril-hx), where `Person` is the corresponding `DataClass` for the above form:

```haxe
m("input[placeholder='First name']", {
	"class": if(Person.validateName(form.firstName)) null else "error",
	value: form.firstName,
	oninput: e -> form.firstName = e.target.value
})
```

When submitting the form, [dataMap](https://github.com/ciscoheat/dataclass/wiki/DataMap) can then be used to create the actual `DataClass` required by the business logic.

## Exceptions

When a DataClass object is instantiated but the input fails validaton, a `dataclass.DataClassException` is thrown:

```haxe
try new Person({
	id: 2,
	email: "no email"
}) catch(e : DataClassException) {
	trace(e.errors);    // DataClassErrors
	trace(e.dataClass); // The failed object
	trace(e.data);      // The failed data
}
```

## Equality comparison

Use a library like [deep_equal](https://lib.haxe.org/p/deep_equal/) for value comparison between `DataClass` objects.

## JSON/Date conversion

DataClass can ease the JSON conversion process, especially when using `Date`. When defining `-D dataclass-date-auto-conversion`, strings and numbers will be automatically converted to `Date`, so you can basically create DataClass objects directly from JSON:

```haxe
class Test implements DataClass {
	public final id : Int;
	public final created : Date;
}

final json = haxe.Json.parse('{"id":123,"created":"2019-05-05T06:10:24.428Z"}');
final t = new Test(json);

trace(t.created.getFullYear());
```

This works with strings in the javascript json format `2012-04-23T18:25:43.511Z` and numbers representing the number of milliseconds elapsed since 1st January 1970. An exception is when targeting javascript, where the native [Date](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date) methods will be used, making it possible to store the date in many different formats.

## Installation

`haxelib install dataclass`, then put `-lib dataclass` in your `.hxml` file.

## Connection to DCI

Simple objects are used in the Data part of the [DCI architecture](https://en.wikipedia.org/wiki/Data,_context_and_interaction). They represent what the system *is*, and have no connections to other objects. They play Roles in DCI Contexts, where they become parts of Interactions between other objects, describing what the system *does* based on a user mental model. The [haxedci-example](https://github.com/ciscoheat/haxedci-example) repository has a thorough tutorial of the DCI paradigm in Haxe if you're interested.

[![Build Status](https://travis-ci.org/ciscoheat/dataclass.svg?branch=master)](https://travis-ci.org/ciscoheat/dataclass)
