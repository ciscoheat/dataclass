import haxe.ds.Option;

typedef MutableJson = haxe.DynamicAccess<Dynamic>;

class Parent implements DataClass {
	@:validate(_ > 0) public final id : Int;
}

// PHP bug in Haxe 4 RC 2
#if !php
interface Status
{
	// Validation added to implementing classes
	@:validate(_ != MethodNotAllowed)
	final status : Tests2.HttpStatus;
}
#end

@:publicFields class Dataclass2 #if !php implements Status #end extends Parent
{
	final name : Null<String>;  // Null<T> allows null

	@:validate(_.length >= 2)    // Expression validation, "_" is replaced with the field
	final city : Null<String>;

	final email : String;

	@:validate(~/^[24]/) 	// // Regexp validation (remember ^ and $) testing string converted value
	final status : Tests2.HttpStatus = NotFound; // Enum abstracts

	///// Default values /////

	final active : Bool = true;         	 // Default value
	final color : Tests2.Color = Rgb(1,2,3); // Works for Enums
	final created : Date = Date.now();  	 // And any statement
	
	@:validate(_.equals(Some("ok")))
	final defaultOption : haxe.ds.Option<String> = Some("ok");
	final avoidNull : Option<String> = None;

	///// JSON options /////

	final jsonData : ds.ImmutableJson = {"test": 123}; 	// JSON object data or anonymous structure
	public final mutableJson : MutableJson = {};

	// Method test
	public function yearCreated() return created.getFullYear();
}
