
import buddy.*;
using buddy.Should;

class RequireId implements DataClass
{
	// Not null, so id is required
	public var id : Int;
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
	@val("\\d{4}-\\d\\d-\\d\\d") public var date : String;
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
			
			describe("With a string validator", {
				it("should validate the whole string as an EReg", {
					new Validator({ date: "2015-12-12" } );
					(function() new Validator({	date: "AAA" })).should.throwType(String);
				});
			});			
		});
	}
}
