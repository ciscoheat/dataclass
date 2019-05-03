import haxe.ds.Option;

typedef MutableJson = haxe.DynamicAccess<Dynamic>;

class Parent implements DataClass {
	@:validate(_ > 0) public final id : Int;
}

interface Status
{
	// Validation added to implementing classes
	@:validate(_ != MethodNotAllowed)
	final status : Tests2.HttpStatus;
}

@:publicFields class Dataclass2 implements Status extends Parent
{
	final name : Null<String>;  // Null<T> allows null

	@validate(_.length >= 2)    // Expression validation, "_" is replaced with the field
	public final city : Null<String>;

	public final email : String;

	@:validate(~/^[24]/) 	// // Regexp validation (remember ^ and $) testing string converted value
	public final status : Tests2.HttpStatus = NotFound; // Enum abstracts

	///// Default values /////

	final active : Bool = true;         			// Default value
	public final color : Tests2.Color = Rgb(1,2,3); // Works for Enums
	public final created : Date = Date.now();  		// And any statement

	///// Null safety /////

	//public final nullDef : Null<String> = "invalid"; // Compilation error, cannot have null with def. value
	public final avoidNull : Option<String>; // = None is automatically added.

	@:validate(_ == "ok") @:validate(_ != "NOk")	// Validation for Option is tested for the wrapped value
	public final defaultOption : haxe.ds.Option<String> = "ok"; // = "ok" Will become Some("ok")

	///// JSON options /////

	public final jsonData : ds.ImmutableJson = {"test": 123}; 	// JSON object data or anonymous structure
	public final mutableJson : MutableJson = {};

	// Method test
	public function yearCreated() return created.getFullYear();
}
