
import buddy.*;
using buddy.Should;

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
}

class HasProperty implements DataClass
{
	// Should work on null properties
	public var a(default, null) : String;

	// Should work on default properties
	public var b(default, default) : String;
}

class Child extends HasProperty
{
	public var child : Bool;
}

class Validator implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_ > 1000) public var int : Int;
}

class StringConverter implements DataClass.StringDataClass
{
	public var date : String;
	public var bool : Bool;
	@validate(_ > 1000) public var int : Int;
}

class FloatConverter implements DataClass.StringDataClass
{
	public var float : Null<Float>;
}

class Tests extends BuddySuite implements Buddy<[Tests]>
{	
	public function new() {
		describe("DataClass", {
			describe("With non-null fields", {
				it("should not compile if non-null value is missing", {
					new RequireId({id: 123}).id.should.be(123);
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
					new DefaultValue({}).city.should.be("Nowhere");
				});
				it("should be set to the supplied value if field value is supplied", {
					new DefaultValue({city: "Somewhere"}).city.should.be("Somewhere");
				});
			});

			describe("With property fields", {
				it("should be set as with var fields", {
					var prop = new HasProperty({
						a: "A",
						b: "B",
					});
					
					prop.a.should.be('A');
					prop.b.should.be('B');
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
						a: "A",
						b: "B",
						child: true
					});
					
					prop.a.should.be('A');
					prop.b.should.be('B');
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
		});
		
		describe("StringDataClass", {
			it("should convert string values to the correct type.", {
				var data = {
					date: "2015-12-12",
					bool: "1",
					int: "2000"
				};
				
				var a = new StringConverter(data);
				
				a.date.should.be("2015-12-12");
				a.bool.should.be(true);
				a.int.should.be(2000);
			});

			it("should fail unless validated.", {
				var data = {
					date: "2015-12-12",
					bool: "1",
					int: "100"
				};
				
				(function() new StringConverter(data)).should.throwType(String);
			});
			
			it("should parse floats correctly", {
				var data = { float: "123345.44" };
				new FloatConverter(data).float.should.beCloseTo(123345.44);
			});
			
			it("should parse money format correctly", {
				var data = { float: "$123.345,44" };
				new FloatConverter(data).float.should.beCloseTo(123345.44);
			});
		});
		
	}
}
