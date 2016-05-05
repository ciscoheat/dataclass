package dataclass;

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
	public static function nullTestAllowed(type : ComplexType) {
		var staticPlatform = Context.defined("cpp") || Context.defined("java") || Context.defined("flash") || Context.defined("cs");
		if (!staticPlatform) return true;
		
		return switch type {
			case TPath(p): !(p.pack.length == 0 && ['Int', 'Float', 'Bool'].has(p.name));
			case _: true;
		}
	}
	
	public static function createValidator(type : ComplexType, paramName : Expr, optional : Bool, e : Expr, failExpr : Expr) : Expr {
		function replaceParam(e : Expr) return switch e.expr { 
			case EConst(CIdent("_")): macro $paramName;
			case _: e.map(replaceParam);
		}
		
		var test = switch e.expr {
			case EConst(CRegexp(r, optional)):
				if (!r.startsWith('^') && !r.endsWith('$')) r = '^' + r + "$";
				macro new EReg($v{r}, $v{optional}).match($paramName);
			case _: 
				replaceParam(e);
		}
		
		// If normal validation, fine. If called from static validate method, 
		// test if paramName is null, then false.
		if(nullTestAllowed(type))
			test = macro if ($paramName == null) false else $test;
		
		return nullTestAllowed(type)
			? macro if ((!$v{optional} || $paramName != null) && !$test) $failExpr
			: macro if (!$v{optional} && !$test) $failExpr;
	}
}
#end
