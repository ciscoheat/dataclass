# DataClass

A more convenient way to instantiate data classes.

```haxe
enum Color { Red; Blue; }

class Person implements DataClass {
	public var id : Int 			 // Required
	public var name : Null<String>	 // Optional

	@validate(~/[\w-.]+@[\w-.]+/)	 			// Regexp validation
	public var email(default, null) : String	// Works with "default" and "null" proprerties

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
class Custom implements DataClass {
	public function new(data) {
		// Code here...
	}
}
```

At the top of this constructor, all the assignments will be inserted. So when running it will look similar to this:

```haxe
class Custom implements DataClass {
	public var id : Int;
	
	public function new(data) {
		this.id = data.id;
		// Code here...
	}
}
```

## Conversion utilities

