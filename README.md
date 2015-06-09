# DataClass

A more convenient way to instantiate simple data classes.

```haxe
class Person implements DataClass {
	public var id : Int 			 // Required
	public var name : Null<String>	 // Optional

	@validate(~/[\w-.]+@[\w-.]+/)	 // Regexp validation
	public var email : String

	@validate(_.length > 2)			 // Expression validation
	public var city : String 

	public var active : Bool = true; // Default value
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
