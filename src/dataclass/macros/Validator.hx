package dataclass.macros;
import haxe.ds.Option;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using Lambda;
using StringTools;

class Validator
{
	// Complications: Testing for null is only allowed if on a non-static platform or the type is not a basic type.
	public static function nullTestAllowed(type : ComplexType) : Bool {
		var staticPlatform = Context.defined("cpp") || Context.defined("java") || Context.defined("flash") || Context.defined("cs");
		if (!staticPlatform) return true;
		
		return switch type {
			case TPath(p): !(p.pack.length == 0 && ['Int', 'Float', 'Bool'].has(p.name));
			case _: true;
		}
	}
	
	// TODO: Verify that Null<Int> cannot be used on static platforms
	// Returns an Expr that, if true, should fail validation.
	public static function createValidatorTestExpr(
		type : ComplexType, field : Expr, isOptional : Bool, validators : Array<Expr>) : Option<Expr> {
		/*
		var fieldExists = if (fieldMustExist) {
			var f = field.toString().split(".");
			macro Reflect.hasField($i{f[0]}, $v{f[1]});
		} else macro true;
		*/
		
		// TODO: Support more than one validator
		if (validators.length > 1) 
			Context.error("Currently only one @validate() is supported per field", validators[1].pos);
		
		var cannotBeNull = !isOptional && nullTestAllowed(type);
		
		var validatorTests = validators.map(function(validator) {
			function replaceParam(e : Expr) return switch e.expr { 
				case EConst(CIdent("_")): macro $field;
				case _: e.map(replaceParam);
			}
			
			return switch validator.expr {
				case EConst(CRegexp(r, opt)):
					if (!r.startsWith('^') && !r.endsWith('$')) r = '^' + r + "$";
					macro new EReg($v{r}, $v{opt}).match($field);
				case _: 
					replaceParam(validator);
			}
		});
		
		var testExpr = if (validatorTests.length == 0 && cannotBeNull) {
			macro $field == null;
		} else if (validatorTests.length > 0) {
			var test = validatorTests[0];
			if (cannotBeNull) macro $field == null || !($test);
			else macro $field != null && !($test);
		} else {
			null;
		}
		
		//trace(testExpr.toString());
		return testExpr == null ? Option.None : Option.Some(testExpr);
	}
}
#end
