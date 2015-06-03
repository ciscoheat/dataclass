
import buddy.*;
using buddy.Should;

class Tests extends BuddySuite implements Buddy<[Tests]>
{	
	public function new() {
		describe("Main", {
			it("should return 123 from value()", {
				new Main().value().should.be(123);
			});
		});
	}
}
