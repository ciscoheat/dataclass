package dataclass.macros;

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
	
	public static function createValidator(type : ComplexType, field : Expr, isOptional : Bool, validator : Null<Expr>, failExpr : Expr, fieldMustExist : Bool) : Expr {
		function replaceParam(e : Expr) return switch e.expr { 
			case EConst(CIdent("_")): macro $field;
			case _: e.map(replaceParam);
		}
		
		var fieldExists = if (fieldMustExist) {
			var f = field.toString().split(".");
			macro Reflect.hasField($i{f[0]}, $v{f[1]});
		} else macro true;
		
		var isNullAndNullIsAllowed = nullTestAllowed(type) ? (macro ($v{isOptional} && $field == null)) : (macro false);
		
		validator = validator == null ? (macro true) : validator;
		
		var validatorTest = switch validator.expr {
			case EConst(CRegexp(r, opt)):
				if (!r.startsWith('^') && !r.endsWith('$')) r = '^' + r + "$";
				macro new EReg($v{r}, $v{opt}).match($field);
			case _: 
				replaceParam(validator);
		}
		
		var output = macro if (!($fieldExists && ($isNullAndNullIsAllowed || $validatorTest))) $failExpr;
		//trace(output.toString());
		return output;
	}
}
#end
