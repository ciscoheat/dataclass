
import haxecontracts.Contract;
import haxecontracts.HaxeContracts;
import haxedci.Context;

using Slambda;
using StringTools;

class Main 
implements HaxeContracts implements Context
{	
	static function main() {
		new Main().start();
	}

	public function new() {
		Contract.requires(true != false, "Uh-oh.");

		this.amount = [100, 20, 3].fold.fn1([i, n] => i + n, 0);
	}
	
	public function start() amount.display();
	public function value() return amount;

	@role var amount : Int = {
		function display() : Void {
			trace(self);
		}
	}

	@invariant function invariants() {
		Contract.invariant(amount == 123, "Amount must always be 123.");
	}
}
