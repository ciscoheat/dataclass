import buddy.*;
import dataclass.*;
import haxe.Json;
import haxecontracts.ContractException;
import haxecontracts.HaxeContracts;

#if cpp
import hxcpp.StaticStd;
import hxcpp.StaticRegexp;
#end

using buddy.Should;
using dataclass.Converter;

enum Color { Red; Blue; }

class RequireId implements DataClass
{
	// Not null, so id is required
	public var id : Int;
}

class IdWithConstructor implements DataClass
{
	public var id : Int;
	
	// Dataclass code will be injected before other things in the constructor.
	public function new(data) {
		// This value will be tested
		this.id = 9876;
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
	public var city : String = "Nowhere";
	public var color = Blue;
	public var date = Date.now();
}

class HasProperty implements DataClass
{
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

class Validator implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_ > 1000) public var int : Int;
}

class NullValidateTest implements DataClass
{
	@validate(_ > 1000) public var int : Null<Int>;
}

// Need @:keep to work in dce=full
@:keep class StringConverter implements DataClass
{
	public var date : String;
	public var bool : Bool;
	@validate(_ > 1000) public var int : Int;
}

// Contains all types supported by the converter.
@:keep class TestConverter implements DataClass
{
	public var bool : Bool;
	public var int : Int;
	public var date : Date;
	public var float : Float;
}

@:keep class TestFloatConverter implements DataClass
{
	public var float : Null<Float>;
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

class Ignore implements dataclass.DataClass {
	public var id : Int;
	@ignore public var input : Array<Int>;
}

@immutable class Immutable implements DataClass
{
	public var id : Int;
	public var name : String;	
}

interface ExtendingInterface extends DataClass
{
}

class Tests extends BuddySuite implements Buddy<[Tests, ConverterTests]>
{	
	public function new() {
		describe("DataClass", {
			describe("With non-null fields", {
				it("should not compile if non-null value is missing", {
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
					o.color.should.be(Color.Blue);
					o.date.should.not.be(null);
					(o.date.getTime() - now.getTime()).should.beLessThan(10);
				});
				it("should be set to the supplied value if field value is supplied", {
					new DefaultValue( { city: "Somewhere" } ).city.should.be("Somewhere");
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
				
				it("should throw an exception when setting a property after instantiation", {
					(function() prop.get_set = "ABC").should.throwType(String);
				});
			});

			describe("With an existing constructor", {
				it("should inject the dataclass code at the top", {
					var prop = new IdWithConstructor({
						id: 1234
					});
					
					// Set in constructor, below the dataclass code.
					prop.id.should.be(9876);
				});
			});

			describe("With @ignore on a field", {
				it("should skip the field altogether", {
					var o = new Ignore({id: 123});
					o.input.should.be(null);
				});
			});

			describe("Validators", {
#if !php
				it("should validate with @validate(...) expressions", function(done) {
					new Validator({ date: "2015-12-12", str: "AAA", int: 1001 });
					done();
				});
#end

				it("should validate regexps as a ^...$ regexp.", {
					(function() new Validator({	date: "*2015-12-12*", str: "AAA", int: 1001 })).should.throwType(String);
				});

				it("should replace _ with the value and validate", {
					(function() new Validator({	date: "2015-12-12", str: "A", int: 1001 })).should.throwType(String);
					(function() new Validator({	date: "2015-12-12", str: "AAA", int: 1 })).should.throwType(String);
				});
				
#if !static
				it("should accept null values if field can be null", {
					new NullValidateTest({ int: null }).int.should.be(null);
					new NullValidateTest().int.should.be(null);
					(function() new NullValidateTest( { int: 1 } )).should.throwType(String);
					new NullValidateTest({ int: 2000 }).int.should.be(2000);
				});
#end

				it("should throw an exception when setting a var to an invalid value after instantiation", {
					var test = new NullValidateTest( { int: 2000 } );
					(function() test.int = 100).should.throwType(String);
				});
			});
			
			describe("Implementing HaxeContracts", {
				it("should throw ContractException instead of a string.", {				
					(function() new TestHaxeContracts({ id: -1 })).should.throwType(ContractException);
				});
			});
			
			describe("Using the @immutable metadata", {
				it("should convert all var fields into (default, null) properties.", {
					// Difficult to test compilations errors...!
					var immutable = new Immutable({ id: 123, name: "Test" });
					immutable.should.beType(Immutable);
					
					//immutable.id = 456;
					immutable.id.should.be(123);
					immutable.name.should.be("Test");					
				});
			});
		});

		describe("DataClass conversions", {
			it("should convert Dynamic to the correct type.", {
				var data = {
					date: "2015-12-12",
					bool: "1",
					int: "2000",
					doesNotExist: "should not be added"
				};
				
				var a = StringConverter.fromDynamic(data);
				
				a.date.should.be("2015-12-12");
				a.bool.should.be(true);
				a.int.should.be(2000);				
			});

			it("should fail unless validated.", {
				var data = Json.parse('{
					"date": "2015-12-12",
					"bool": "1",
					"int": "100"
				}');
				
				#if cs
				try {
					StringConverter.fromDynamic(data);
					fail("Object should fail validation.");
				} catch (e : Dynamic) {
					e.should.not.be(null);
				}
				#else
				(function() StringConverter.fromDynamic(data)).should.throwType(String);
				#end
			});
			
			it("should parse floats correctly", {
				var data = { float: "123345.44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);
			});
			
			it("should parse money format correctly", {
				var old = Converter.delimiter;
				Converter.delimiter = ",";
				
				var data = { float: "$123.345,44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);
				
				Converter.delimiter = old;
			});
			
			it("should parse column data when using the @col metadata", {
				var data = ["123", "2015-01-01", "1"];
				var obj = TestColumnConverter.fromClassData(data);
				
				obj.first.should.be(123);
				obj.second.toString().should.be("2015-01-01 00:00:00");
				obj.third.should.be(true);
			});

			it("should parse column data when using an array of columns", {
				var data = ["123", "2015-01-01", "1"];
				var columns = ["first", "second", "third"];
				var obj = TestColumnConverter.fromColumnData(columns,data);
				
				obj.first.should.be(123);
				obj.second.toString().should.be("2015-01-01 00:00:00");
				obj.third.should.be(true);
			});

			it("should convert public fields to the specified string format.", {
				var a = TestConverter.fromDynamic({
					date: "2015-12-12",
					bool: "1",
					int: "2000",
					float: "123.45"
				});
				
				var o = a.toDynamic({
					delimiter: ',',
					boolValues: { tru: "YES", fals: "NO" },
					dateFormat: "%Y%m%d"
				});
				
				Reflect.fields(o).length.should.be(4);
				a.float.should.be(123.45);
				o.date.should.be("20151212");
				o.bool.should.be("YES");
				o.int.should.be("2000");
				o.float.should.be("123,45");
			});
			
			it("should auto-detect delimiter if set to an empty string", {
				var old = Converter.delimiter;
				Converter.delimiter = "";
				
				var data = { float: "$123.345,44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);

				data = { float: "123 345.44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);

				data = { float: "123345,44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);

				Converter.delimiter = old;				
			});
		});		
	}	
}

class ConverterTests extends BuddySuite
{	
	public function new() {
		describe("Converter", {
			it("should work with the supported types", {
				var data = {
					bool: "true".toBool(),
					int: "123".toInt(),
					date: "2015-01-01 00:00:00".toDate(),
					float: "456.789".toFloat()
				};
				
				var test = new TestConverter(data);
				
				test.bool.should.be(true);
				test.int.should.be(123);
				DateTools.format(test.date, "%Y-%m-%d %H:%M:%S").should.be("2015-01-01 00:00:00");
				test.float.should.beCloseTo(456.789, 3);
				
				test.bool.toString({tru: "YES", fals: "NO"}).should.be("YES");
				(false).toString({tru: "YES", fals: "NO"}).should.be("NO");
				
				test.int.toString().should.be("123");
				test.date.toStringFormat("%Y-%m-%d").should.be("2015-01-01");
				test.float.toString().should.be("456.789");				
			});			
		});
	}
}
