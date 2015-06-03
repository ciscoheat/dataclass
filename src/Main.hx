package;

import haxecontracts.Contract;
import haxecontracts.HaxeContracts;
import haxedci.Context;

using Lambda;
using StringTools;

class Main 
implements HaxeContracts implements Context
{	
	static function main() {
		new Main().start();
	}

	public function new() {
		Contract.requires(true != false, "Uh-oh.");
		this.amount = 123;
	}
	
	public function start() {
		amount.display();
	}

	@role var amount : Int = {
		function display() : Void {
			trace(self);
		}
	}
}
