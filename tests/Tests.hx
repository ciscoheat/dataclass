import DataClass;
import buddy.*;
import dataclass.*;
import haxe.DynamicAccess;
import haxe.Json;
import haxe.rtti.Meta;
import haxecontracts.ContractException;
import haxecontracts.HaxeContracts;
import subpack.AnotherConverter;

#if cpp
import hxcpp.StaticStd;
import hxcpp.StaticRegexp;
#end

using StringTools;
using buddy.Should;

using dataclass.JsonConverter;
import dataclass.CsvConverter;

@:enum abstract HttpStatus(Int) {
	var NotFound = 404;
	var MethodNotAllowed = 405;
}

enum Color { Red; Blue; } //Rgb(r: Int, g: Int, b: Int); }

class RequireId implements DataClass
{
	// Not null, so id is required
	public var id : Int;
}

class IdWithConstructor implements DataClass
{
	public var id : Int;
	@exclude public var initialId : Int;
	@exclude public var defaultParameter : String;
	@exclude public var nullParameter : String;
	@exclude public var extra : String;
	
	// Dataclass code will be injected before other things in the constructor.
	public function new(data : {extra : String}, second = "ok", ?third : String) {
		// This value will be tested
		this.id = 9876;
		this.defaultParameter = second;
		this.nullParameter = third;
		
		// Test if type is correct
		initialId = data.id;
		
		// Extra parameter assignment
		this.extra = data.extra;
	}
}

class AllowNull implements DataClass
{
	// Null value is ok
	public var name : Null<String>;
}

class DefaultValue implements DataClass
{
	// Default value set if no other supplied
	@validate(_.length > 0) public var city : String = "Nowhere";
	public var color : Color = Blue;
	public var date : Date = Date.now();
	public var status : HttpStatus = NotFound;
}

class HasProperty implements DataClass
{
	@validate(_.length == 0)
	public var called : Array<String> = [];
	
	public var def_null(default, null) : String;

	public var def_def(default, default) : String;
	
	@validate(_.length == 1)
	public var get_set(get, set) : String;
	function set_get_set(v : String) {
		called.push("set_get_set");
		return _get_set = v;
	}
	function get_get_set() {
		called.push("get_get_set");
		return _get_set;
	}
	var _get_set : String;

	public var get_null(get, null) : String;
	function get_get_null() {
		called.push("get_get_null");
		return get_null;
	}
	
	public var def_null_defValue(default, null) : String = "def_null_defValue";
}

@immutable class HasPropertyWithImmutable implements DataClass
{
	public var def_null(default, null) : String;
	public var def_never(default, never) : String;
	public var def_never_defValue(default, never) : String = "def_never_defValue";
	public var def_null_defValue(default, null) : String = "def_null_defValue";
}

class Validator implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_ > 1000) public var integ : Int;
}

class NullValidateTest implements DataClass
{
	// Field cannot be called "int" on flash!
	@validate(_ > 1000) public var integ : Null<Int>;
}

// Need @:keep to work in dce=full
@:keep class StringConverter implements DataClass
{
	public var date : String;
	public var bool : Bool;
	@validate(_ > 1000) public var integ : Int;
	public var anything : String;
}

// Contains all types supported by the converter.
@:keep class TestConverter implements DataClass
{
	public var bool : Bool;
	public var integ : Int;
	public var date : Date;
	public var float : Float;
}

@:keep class TestFloatConverter implements DataClass
{
	public var float : Null<Float>;
}

// Testing how convertTo reacts on a different type
@:keep class TestFakeFloatConverter implements DataClass
{
	public var float : String;
}

@:keep class TestColumnConverter implements DataClass
{
	@col(1) public var first : Int;
	@col(3) public var third : Bool;
	@col(2) public var second : Date;
	
	var internal : String;
}

class TestHaxeContracts implements DataClass implements HaxeContracts
{
	@validate(_ > 0) public var id : Null<Int>;
}

class ExcludeTest implements DataClass {
	public var id : Int;
	@exclude public var input : Array<Int>;
}

class IncludeTest implements DataClass {
	@include var id : Int;	
	public function itsId() return id;
	public var notUsed : String = "not used";
}

@immutable class ImmutableClass implements DataClass
{
	public var id : Int;
	public var name(default, null) : String;
}

class CircularReferenceTest implements DataClass
{
	public var id : Int;
	public var children(default, null) : Array<CircularReferenceTest> = [];
	public var parent : Null<CircularReferenceTest>;
}

interface ExtendingInterface extends DataClass
{
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

class Tests extends BuddySuite implements Buddy<[
	Tests, 
	ConverterTests, 
	InheritanceTests
]>
{	
	public function new() {
		describe("DataClass", {
			describe("With non-null fields", {
				it("should not compile if non-null value is missing", {
					CompilationShould.failFor(new RequireId()).should.startWith("Not enough arguments");
					CompilationShould.failFor(new RequireId({})).should.startWith("Object requires field id");
					new RequireId( { id: 123 } ).id.should.be(123);
				});

#if !static
				it("should throw if null value is supplied", {
					(function() new RequireId({id: null})).should.throwType(String);
				});

				it("should throw an exception when setting the var to null after instantiation", {
					var id = new RequireId( { id: 123 } );
					(function() id.id = null).should.throwType(String);
				});
#end
			});

			describe("With null fields", {
				it("should compile if all fields are null and nothing is passed to the constructor", {
					new AllowNull().name.should.be(null);
				});
				it("should compile if field value is missing", {
					new AllowNull({}).name.should.be(null);
				});
				it("should compile if null value is supplied as field", {
					new AllowNull({name: null}).name.should.be(null);
				});
			});
			
			describe("With default values", {				
				it("should be set to default if field value isn't supplied", {
					var now = Date.now();
					var o = new DefaultValue();
					
					o.city.should.be("Nowhere");
					o.color.should.equal(Color.Blue);
					o.date.should.not.be(null);
					(o.date.getTime() - now.getTime()).should.beLessThan(100);
				});
				it("should be set to the supplied value if field value is supplied", {
					new DefaultValue( { city: "Somewhere" } ).city.should.be("Somewhere");
				});
				
				it("should fail validation if set to an invalid value", {
					var o = new DefaultValue();
					(function() o.city = "").should.throwType(String);
					(function() o.date = null).should.throwType(String);
				});
			});

			describe("With property fields", {
				var prop : HasProperty;
				
				beforeEach({
					prop = new HasProperty({
						def_def: "A",
						def_null: "B",
						get_set: "C",
						get_null: "D"
					});
				});
				
				it("should be set as with var fields", {
					prop.def_def.should.be('A');
					prop.def_null.should.be('B');
					prop.get_set.should.be('C');
					prop.get_null.should.be('D');
					prop.def_null_defValue.should.be('def_null_defValue');
					
					prop.called.should.containAll(['set_get_set', 'get_get_set', 'get_get_null']);
				});
				
				it("should throw an exception when setting a property to an invalid value after instantiation", {
					(function() prop.get_set = "ABC").should.throwType(String);
				});	
				
				it("should not be possible to assign to def_null", {
					CompilationShould.failFor(prop.def_null = "assigned");
				});
			});

			describe("With an existing constructor", {
				it("should inject the dataclass code at the top", {
					var prop2 = new IdWithConstructor({
						id: 1234,
						extra: "extraField"
					});
					
					// Set in constructor
					prop2.id.should.be(9876);
					prop2.initialId.should.be(1234);
					prop2.defaultParameter.should.be("ok");
					prop2.nullParameter.should.be(null);
					prop2.extra.should.be("extraField");
				});
			});

			describe("With @exclude on a public field", {
				it("should skip the field altogether", {
					var o2 = new ExcludeTest({ id: 123 });
					o2.input.should.be(null);
				});
			});

			describe("With @include on a private field", {
				it("should include the field", {
					var o3 = new IncludeTest({ id: 123 });					
					o3.itsId().should.be(123);
					o3.notUsed.should.be("not used");
				});
			});

			describe("Validators", {
				it("should validate with @validate(...) expressions", {
					(function() new Validator({ date: "2015-12-12", str: "AAA", integ: 1001 })).should.not.throwAnything();
				});

				it("should validate regexps as a ^...$ regexp.", {
					(function() new Validator({	date: "*2015-12-12*", str: "AAA", integ: 1001 })).should.throwType(String);
				});

				it("should replace _ with the value and validate", {
					(function() new Validator({	date: "2015-12-12", str: "A", integ: 1001 })).should.throwType(String);
					(function() new Validator({	date: "2015-12-12", str: "AAA", integ: 1 })).should.throwType(String);
				});
				
#if !static
				it("should accept null values if field can be null", {
					new NullValidateTest({ integ: null }).integ.should.be(null);
					new NullValidateTest().integ.should.be(null);
					(function() new NullValidateTest( { integ: 1 } )).should.throwType(String);
					new NullValidateTest({ integ: 2000 }).integ.should.be(2000);
				});
#end

				it("should throw an exception when setting a var to an invalid value after instantiation", {
					var test = new NullValidateTest( { integ: 2000 } );
					test.integ.should.be(2000);
#if !static
					test.integ = null;
					test.integ.should.be(null);
#end
					test.integ = 3000;
					test.integ.should.be(3000);
					(function() test.integ = 100).should.throwType(String);
					test.integ.should.be(3000);
				});
			});
			
			describe("Manual validation", {
				it("should be done using the static 'validate' field", {
					Validator.validate({}).should.containAll(['date', 'str', 'integ']);
					Validator.validate({}).length.should.be(3);
					
					Validator.validate({ date: "2016-05-06" }).should.containAll(['str', 'integ']);
					Validator.validate( { date: "2016-05-06" } ).length.should.be(2);
					
					//var a = new Validator(
					
					var input = { integ: 1001, date: "2016-05-06", str: "AAA" };
					Validator.validate(input).length.should.be(0);
					
					RequireId.validate({}).should.contain("id");
					RequireId.validate({id: 1001}).length.should.be(0);
				});
				
				it("should fail a default value field if it exists but has an incorrect value", {
					HasProperty.validate({}).should.containAll(['def_null', 'def_def', 'get_set', 'get_null']);
					HasProperty.validate({}).length.should.be(4);
					
					HasProperty.validate( { called: ["should fail"] } ).should.containAll(
						['called', 'def_null', 'def_def', 'get_set', 'get_null']
					);
					HasProperty.validate( { called: ["should fail"] } ).length.should.be(5);					
				});
			});
			
			describe("Implementing HaxeContracts", {
				it("should throw ContractException instead of a string.", {				
					(function() new TestHaxeContracts({ id: -1 })).should.throwType(ContractException);
				});
			});
			
			describe("Using the @immutable metadata", {
				it("should convert all var fields into (default, null) properties.", {
					var immutable = new ImmutableClass( { id: 123, name: "Test" } );
					CompilationShould.failFor(immutable.id = 456);
					CompilationShould.failFor(immutable.name = "Not a test");
				});
			});
		});
	}	
}

class DeepTest implements DataClass {
	public var id : String;
	public var single : DeepConverter;
	public var array : Array<ImmutableClass>;
	public var csv : Array<Array<String>>;
	@exclude public var unconvertable : Array<String -> Int>;
}

class ConverterTests extends BuddySuite
{	
	public function new() {
		describe("Enum conversion", {
			it("should be possible to convert strings to simple Enums and back", {
				var input = "Red";
				var type = Type.resolveEnum("Color");
				
				var obj = new DefaultValue({
					color: Type.createEnum(type, input)
				});
				
				obj.color.should.equal(Color.Red);
				obj.status.should.be(HttpStatus.NotFound);
				
				var json = obj.toJson();
				var reconverted = DefaultValue.fromJson(json);
				
				cast(json.get("date"), String).should.match(~/^.*T.*Z$/);
				
				Json.stringify(json).should.be(Json.stringify(reconverted.toJson()));
			});
		});
		
		describe("Converter", {
			describe("JSON", {
				var conv1 : DeepTest;
				var json = {
					id: "id",
					single: {
						integ: 100,
						another: {
							bool: true,
							integ: 1,
							date: "2017-01-18T00:58:00Z",
							float: 3.1416
						}
					},
					array: [
						{ id: 1, name: "1" },
						{ id: 2, name: "2" }
					],
					csv: [
						['123', '456', '789'],
						['987', '654', '321']
					]
				};
				
				beforeEach({
					conv1 = DeepTest.fromJson(json);
				});
					
				it("should convert json to DataClass", {
					conv1.id.should.be("id");
					
					conv1.single.integ.should.be(100);
					
					conv1.single.another.bool.should.be(true);
					conv1.single.another.integ.should.be(1);
					conv1.single.another.date.getFullYear().should.be(2017);
					conv1.single.another.date.getMonth().should.be(0);
					conv1.single.another.float.should.beCloseTo(3.1416, 4);
					
					conv1.array.length.should.be(2);
					conv1.array[0].id.should.be(1);
					conv1.array[0].name.should.be("1");
					conv1.array[1].id.should.be(2);
					conv1.array[1].name.should.be("2");
					
					conv1.csv.length.should.be(2);
					conv1.csv[0].length.should.be(3);
					conv1.csv[1].length.should.be(3);
				});
				
				it("should convert a DataClass to json", {
					var oj = conv1.toJson();
					
					oj['id'].should.be("id");
					
					var single : DynamicAccess<Dynamic> = oj['single'];
					single['integ'].should.be(100);
					
					var another : DynamicAccess<Dynamic> = single['another'];
					another['bool'].should.be(true);
					cast(another['date'], String).should.match(~/^2017-01-\d\dT.*Z$/);
					
					oj['array'].length.should.be(2);
					var array : DynamicAccess<Dynamic> = oj['array'][0];
					array.get('name').should.be("1");
					
					var csv : Array<Array<String>> = oj['csv'];
					csv.length.should.be(2);
					var innerCsv = csv[0];
					innerCsv[0].should.be("123");
				});
				it("should throw on circular references and set to null if configured like that", {
					var parent = new CircularReferenceTest({id: 1, children: [], parent: null});
					var child = new CircularReferenceTest( { id: 2, children: [], parent: parent } );
					parent.children.push(child);
					
					(function() parent.toJson()).should.throwType(String);
					
					var oldConverter = JsonConverter.current;
					JsonConverter.current = new JsonConverter({nullifyCircularReferences: true});
					
					var nonCirc = parent.toJson();
					var children : Array<DynamicAccess<Dynamic>> = nonCirc.get('children'); 
					children[0].get('parent').should.be(null);
					
					JsonConverter.current = oldConverter;
				});
			});
			
			describe("CSV", {
				var csvDataArray = [
					new TestConverter(
						{bool: true, integ: 123, date: Date.fromString("2017-01-18 05:14:00"), float: 123.456 }
					),
					new TestConverter(
						{bool: false, integ: -123, date: Date.fromString("2000-01-01 00:00:00"), float: -123.456 }
					)
				];
				
				var csvData = [
					['bool', 'integ', 'date', 'float'],
					['1', '123', "2017-01-18 05:14:00", '123,456'],
					['0', '-123', "2000-01-01 00:00:00", '-123,456']
				];
				
				var converter = new CsvConverter({floatDelimiter: ","});
				
				it("should convert CSV to DataClass", {
					var csvC = converter.fromCsvArray(csvData, TestConverter);
					csvC.length.should.be(2);
					
					csvC[0].bool.should.be(true);
					csvC[0].integ.should.be(123);
					csvC[0].date.getFullYear().should.be(2017);
					csvC[0].float.should.beCloseTo(123.456, 3);

					csvC[1].bool.should.be(false);
					csvC[1].integ.should.be(-123);
					csvC[1].date.getFullYear().should.be(2000);
					csvC[1].float.should.beCloseTo(-123.456, 3);
				});
				it("should convert DataClass to CSV", {
					var csvO = converter.toCsvArray(csvDataArray);
					csvO.length.should.be(3);
					for (i in 0...3) csvO[i].length.should.be(4);
					csvO[0].should.containAll(csvData[0]);
					csvO[1].should.containAll(csvData[1]);
					csvO[2].should.containAll(csvData[2]);
				});
			});
		});
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////

class Document
{
	@ignore public var _id(default, null) : Null<String>;
	@validate(_ == null || _.length > 0) public var _key(default, set) : Null<String>;
	public var _rev(default, null) : Null<String>;
	
	function set__key(v : String) {
		#if !python
		// Possibly python compilation bug:
		// AttributeError("'SomePerson' object has no attribute '_key'",)
		if (_key != null) throw '_key already exists: $_key';
		#end
		if (v == null) throw '_key cannot be null';
		return _key = v;
	}
}

// SomePerson should now include the _key attribute.
class SomePerson extends Document implements DataClass
{
	@validate(_.length > 0) public var name : String;
	@validate(_.indexOf("@") > 0) public var email : String;
}

class InheritanceTests extends BuddySuite
{
	public function new() {
		describe("When inheriting from another class", {
			it("should required the public and @included fields in the constructor", {
				var p = new SomePerson({
					_key: "1",
					name: "Test Person",
					email: "test@example.com"
				});

				p.name.should.be("Test Person");
				p._key.should.be("1");
				#if !python
				(function() p._key = "2").should.throwType(String);
				#end
				(function() p._key = null).should.throwType(String);
			});
			
			it("should set the parent fields when using the dynamic converter", {
				var data = {
					_key: "1",
					name: "Test Person",
					email: "test@example.com",
					notused: 123456
				};
				
				var p = SomePerson.fromJson(data);
				p.name.should.be("Test Person");
				p._key.should.be("1");
				p.email.should.be("test@example.com");
			});
		});
	}
}
