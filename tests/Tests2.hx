import buddy.*;
import haxe.Json;
import haxe.ds.Option;

/*
#if cpp
import hxcpp.StaticStd;
import hxcpp.StaticRegexp;
#end
*/

using buddy.Should;
using Dataclass2;

class Tests2 extends BuddySuite implements Buddy<[
	Tests2, 
]>
{	
	public function new() {
		describe("DataClass", {
			it("Should instantiate", {
				final test = new Dataclass2({
					id: 123,
					email: "test@example.com",
					city: "Punxuatawney",
					//avoidNull: Some("value"),
					active: false
				});
				test.id.should.be(123);

				final test2 = test.copy();
				test2.id.should.be(123);

				final test3 = Dataclass2.copy(test2, {id: 234});
				test3.id.should.be(234);
			});

			it("Should work according to the concept class", {
				final test = new Dataclass2({
					id: 123,
					email: "test@example.com",
					city: "Punxuatawney",
					//avoidNull: Some("value"),
					active: false
				});
				test.active.should.be(false);
				
				final testNew = new Dataclass2(test);
				Sys.println(testNew);

				final json = Json.stringify(test, "	");	
				Sys.println(json);
				final data2 : Dynamic = Json.parse(json);
				//data2.created = new js.Date(data2.created);
				Sys.println(data2);

				final test2 = new Dataclass2(data2);
				Sys.println(test2); Sys.println(test2.creationYear());
			});
		});
	}	
}
