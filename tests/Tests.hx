
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

/*
class Combined implements DataClass
{
	// Not null, so id is required
	public var id : Int;
	
	// Null value is ok
	public var name : Null<String>;
	
	// Default value set if no other supplied
	//public var city : String = "Nowhere";
}
*/

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
		});
	}
}
