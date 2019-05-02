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

typedef DataClassErrors = Map<String, Option<Any>>;

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
	/*
	public function new(data : PersonConstructor) {
		switch validate(data) {
			case Some(errors): throw errors;
			case None:
		}

		if(data.name != null) this.name = data.name;
		if(data.city != null) this.city = data.city;
		if(data.email != null) this.email = data.email;
		if(data.status != null) this.status = data.status;
		if(data.active != null) this.active = data.active;
		if(data.color != null) this.color = data.color;
		if(data.created != null) {
	*/
			/*
			#if js
			// With -D dataclass-js-date-auto-conversion
			if(Std.is(data.created, String)) this.created = cast new js.Date(cast data.created);
			else if(Std.is(data.created, Float) || Std.is(data.created, Int)) this.created = cast new js.Date(cast data.created);
			else this.created = data.created;
			#else
			// With -D dataclass-date-auto-conversion
			if(Std.is(data.created, String)) this.created = cast Date.fromString(cast data.created);
			else if(Std.is(data.created, Float) || Std.is(data.created, Int)) this.created = cast Date.fromTime(cast data.created);
			else this.created = data.created;
			#end

			// Else
			*/
	/*
			this.created = data.created;
		}
		if(data.avoidNull != null) this.avoidNull = data.avoidNull;
		if(data.defaultOption != null) this.defaultOption = data.defaultOption;
		if(data.jsonData != null) this.jsonData = data.jsonData;
		if(data.mutableJson != null) this.mutableJson = data.mutableJson;

		super(cast data);
	}
	*/

	/*
	public function copy(?update : {
		@:optional var id : Int;
		@:optional var name : Null<String>;
		@:optional var city : String;
		@:optional var email : String;
		@:optional var status : HttpStatus;
		@:optional var active : Bool;
		@:optional var color : Color;
		@:optional var created : Date;
		@:optional var avoidNull : haxe.ds.Option<String>;
		@:optional var defaultOption : haxe.ds.Option<String>;
		@:optional var jsonData : ds.ImmutableJson;
		@:optional var mutableJson : MutableJson;
	}) : Dataclass2 {
		if(update == null) update = {};

		// The hack way:
		for(f in Reflect.fields(this)) {
			if(!Reflect.hasField(update, f)) Reflect.setField(update, f, Reflect.field(this, f));
		}
		// The real way:
		//if(!Reflect.hasField(update, "id")) update.id = this.id;
		//if(!Reflect.hasField(update, "name")) update.name = this.name;
		//if(!Reflect.hasField(update, "city")) update.city = this.city;

		return new Dataclass2(cast update);
	}
	*/

	public final name : Null<String>;  // Null<T> allows null

	@validate(_.length >= 2)    // Expression validation, "_" is replaced with the field
	public final city : Null<String>;

	public final email : String;

	@validate(~/^[24]/) 	// // Regexp validation (remember ^ and $) testing string converted value
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

	// Not optional anymore
	/*
	public static function validate(data : PersonConstructor) : Option<DataClassErrors> {
		// --- Boilerplate -------------------
		var errors : DataClassErrors = null;
		var hasErrors = false;

		function setError(field, value) {
			if(errors == null) errors = new DataClassErrors();
			errors.set(field, value);
			hasErrors = true;
		}
		// -----------------------------------
	*/
	/*
		// From parent
		// (3) No default value, cannot be null, has validator
		if(data.id == null)
			setError("id", None)
		else if(!(data.id > 0))
			setError("id", Some(data.id));

		// (2) No default value, can be null, has validator
		if(!(data.city.length >= 2))
			setError("city", Some(data.city));

		// (1) No default value, cannot be null, no validator
		if(data.email == null) 
			setError("email", None);

		// (4) Has default value, has validator
		if(data.status == null) 
			null
		else if(!(~/^[24]/.match(Std.string(data.status))) || !(data.status != MethodNotAllowed))
			setError("status", Some(data.status));

		// (4) Has default value, has validator
		if(data.defaultOption == null) 
			null
		else if(!(data.defaultOption.equals(Some("ok")))) // Using equals for Option<T>
			setError("defaultOption", Some(data.defaultOption));

		return hasErrors ? Some(errors) : None;
	}
	*/

	//public function creationYear() return created.getFullYear();
}

// Auto-generated (constructor argument)
typedef PersonConstructor = {
	final id : Int;
	@:optional final name : Null<String>;
	@:optional final city : String;
	final email : String;
	@:optional final status : HttpStatus;
	@:optional final active : Bool;
	@:optional final color : Color;
	@:optional final created : Date;
	@:optional final avoidNull : haxe.ds.Option<String>;
	@:optional final defaultOption : haxe.ds.Option<String>;
	@:optional final jsonData : ds.ImmutableJson;
	@:optional final mutableJson : MutableJson;
}

// Errors throw:
//throw new DataClassException<T>(errorFields : DataClassErrors, dataClassObject : T);