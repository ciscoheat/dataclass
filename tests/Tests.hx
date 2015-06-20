
import buddy.*;
import dataclass.*;
import haxe.Json;
import haxecontracts.ContractException;
import haxecontracts.HaxeContracts;

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
	public var color : Color = Blue;
	public var date : Date = Date.now();
}

class HasProperty implements DataClass
{
	public var def_null(default, null) : String;

	public var def_def(default, default) : String;
	
	public var get_set(get, set) : String;
	var _get_set : String;
	function set_get_set(v : String) return _get_set = v;
	function get_get_set() return _get_set;

	public var get_null(get, null) : String;
	function get_get_null() return get_null;
	
	public var def_null_defValue(default, null) : String = "def_null_defValue";
}

class Child extends DefaultValue
{
	public var child : Bool;
}

class Validator implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_ > 1000) public var int : Int;
}

class StringConverter implements DataClass
{
	public var date : String;
	public var bool : Bool;
	@validate(_ > 1000) public var int : Int;
}

// Contains all types supported by the converter.
class TestConverter implements DataClass
{
	public var bool : Bool;
	public var int : Int;
	public var date : Date;
	public var float : Float;
}

class TestFloatConverter implements DataClass
{
	public var float : Null<Float>;
}

class TestColumnConverter implements DataClass
{
	@col(1) public var first : Int;
	@col(3) public var third : Bool;
	@col(2) public var second : Date;
}

class TestHaxeContracts implements DataClass implements HaxeContracts
{
	public var id : Int;
}

class Tests extends BuddySuite implements Buddy<[Tests, ConverterTests]>
{	
	public function new() {
		describe("DataClass", {
			describe("With non-null fields", {
				it("should not compile if non-null value is missing", {
					new RequireId( { id: 123 } ).id.should.be(123);
				});

				it("should throw if null value is supplied", {
					(function() new RequireId({id: null})).should.throwType(String);
				});
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
					new DefaultValue({city: "Somewhere"}).city.should.be("Somewhere");
				});
			});

			describe("With property fields", {
				it("should be set as with var fields", {
					var prop = new HasProperty({
						def_def: "A",
						def_null: "B",
						get_set: "C",
						get_null: "D"
					});
					
					prop.def_def.should.be('A');
					prop.def_null.should.be('B');
					prop.get_set.should.be('C');
					prop.get_null.should.be('D');
					prop.def_null_defValue.should.be('def_null_defValue');
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

			describe("With a parent class", {
				it("should inherit the required fields", {
					var prop = new Child({
						city: "Punxsutawney",
						color: Red,
						child: true
					});
					
					prop.city.should.be('Punxsutawney');
					prop.color.should.be(Red);
					prop.child.should.be(true);
				});
			});

			describe("Validators", {
				it("should validate with @validate(...) expressions", function(done) {
					new Validator({ date: "2015-12-12", str: "AAA", int: 1001 });
					done();
				});

				it("should validate regexps as a ^...$ regexp.", {
					(function() new Validator({	date: "*2015-12-12*", str: "AAA", int: 1001 })).should.throwType(String);
				});

				it("should replace _ with the value and validate", {
					(function() new Validator({	date: "2015-12-12", str: "A", int: 1001 })).should.throwType(String);
					(function() new Validator({	date: "2015-12-12", str: "AAA", int: 1 })).should.throwType(String);
				});
			});
			
			describe("Implementing HaxeContracts", {
				it("should throw ContractException instead of a string.", {
					(function() new TestHaxeContracts( { id: null } )).should.throwType(ContractException);
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
				
				var a = StringConverter.fromDynamicObject(data);
				
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
				
				(function() StringConverter.fromDynamicObject(data)).should.throwType(String);
			});
			
			it("should parse floats correctly", {
				var data = { float: "123345.44" };
				TestFloatConverter.fromDynamicObject(data).float.should.beCloseTo(123345.44);
			});
			
			it("should parse money format correctly", {
				var old = Converter.delimiter;
				Converter.delimiter = ",";
				
				var data = { float: "$123.345,44" };
				TestFloatConverter.fromDynamicObject(data).float.should.beCloseTo(123345.44);
				
				Converter.delimiter = old;
			});
			
			it("should parse column data when using the @col metadata", {
				var data = ["123", "2015-01-01", "1"];
				var obj = TestColumnConverter.fromColumnData(data);
				
				obj.first.should.be(123);
				obj.second.toString().should.be("2015-01-01 00:00:00");
				obj.third.should.be(true);
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
				test.int.toString().should.be("123");
				test.date.toStringFormat("%Y-%m-%d").should.be("2015-01-01");
				test.float.toString().should.be("456.789");				
			});
		});
	}
}
