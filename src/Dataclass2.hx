import haxe.ds.Option;

enum Color { 
	Red(d : Float); 
	Blue(d : Float); 
}

@:enum
abstract HttpStatus(Int) {
	var NotFound = 404;
	var MethodNotAllowed = 405;
}

typedef MutableJson = haxe.DynamicAccess<Dynamic>;

class Parent implements DataClass {
	// Validation used in child class(es)
	@:validate(_ > 0) public final id : Int;
}

interface Status
{
	// Validation added to implementing classes
	@:validate(_ != MethodNotAllowed)
	final status : HttpStatus;
}

class Dataclass2 implements Status extends Parent
{
	public final name : Null<String>;  // Null<T> allows null

	@validate(_.length >= 2)    // Expression validation, "_" is replaced with the field
	public final city : Null<String>;

	public final email : String;

	@:validate(~/^[24]/) 	// // Regexp validation (remember ^ and $) testing string converted value
	public final status : HttpStatus = NotFound; // Enum abstracts

	///// Default values /////

	public final active : Bool = true;         // Default value
	public final color : Color = Blue(1.0001); // Works for Enums
	public final created : Date = Date.now();  // And statements

	///// Null safety /////

	//public final nullDef : Null<String> = "invalid"; // Compilation error, cannot have null with def. value
	public final avoidNull : Option<String>; // = None is automatically added.

	@:validate(_ == "ok")	// Validation for Option is tested for the wrapped value
	public final defaultOption : haxe.ds.Option<String> = "ok"; // = "ok" Will become Some("ok")

	///// JSON options /////

	public final jsonData : ds.ImmutableJson = {"test": 123}; 	// JSON object data or anonymous structure
	public final mutableJson : MutableJson = {}; 			    // = haxe.DynamicAccess<Dynamic>
	public final illegalJson : haxe.DynamicAccess<Dynamic> = {};

	public function creationYear() return created.getFullYear();
}
