package dataclass.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using Lambda;
using StringTools;

private typedef FieldDataProperties = {
	opt: Bool, 
	def: Expr, 
	val: Expr
}

class Builder
{
	static public function build() : Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass().get();
		
		// Fields aren't available on Context.getLocalClass().
		// need to supply them here. They're available on the superclass though.
		var publicFields = childAndParentFields(fields, cls);
		var fieldMap = new Map<Field, FieldDataProperties>();
		
		// Test if class implements HaxeContracts, then throw ContractException instead.
		var haxeContracts = cls.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == "HaxeContracts";
		});

		// Complicated: Testing for null is only allowed if on a non-static platform or the type is not a basic type.
		function nullTestAllowed(f : Field) {			
			var staticPlatform = Context.defined("cpp") || Context.defined("java") || Context.defined("flash") || Context.defined("cs");
			if (!staticPlatform) return true;
			
			return switch f.kind {
				case FVar(TPath(p), _), FProp(_, _, TPath(p), _):
					if (p.pack.length == 0 && ['Int', 'Float', 'Bool'].has(p.name)) false;
					else true;
				case _: 
					true;
			}
		}

		function throwError(errorString : ExprOf<String>) : Expr {
			return haxeContracts
				? macro throw new haxecontracts.ContractException($errorString, this)
				: macro throw $errorString;
		}

		if (cls.meta.has("immutable")) {
			var replaceThis = ~/^this\./;
			var fieldNames = fields
				.filter(function(f) return publicFields.exists(function(pf) return pf.name == f.name))
				.map(function(f) return f.name);
			
			function preventAssign(e : Expr) switch e.expr {
				case EBinop(OpAssign, e1, _) if (fieldNames.has(replaceThis.replace(e1.toString(), ''))): 
					Context.error("Class " + cls.name + " is marked as immutable, cannot assign to any fields.", e.pos);
				case _: 
					e.iter(preventAssign);
			}
			
			// Make vars and properties into var(default, null) and prevent assignments to fields
			for(f in fields) switch f.kind {
				case FVar(t, e): f.kind = FProp('default', 'null', t, e);
				case FProp(get, _, t, e): f.kind = FProp(get, 'null', t, e);
				case FFun(fun) if(f.name != 'new'): preventAssign(fun.expr);
				case _:
			}
		}

		for (f in publicFields) {
			// If @col metadata, check the format
			for (col in f.meta.filter(function(m) return m.name == "col")) {
				try {
					var param = col.params[0];
					if (!param.expr.match(EConst(CInt(_)))) {
						Context.error("@col can only take a single int as parameter.", param.pos);
					}
				} catch (e : Dynamic) {
					Context.error("@col must take a single int as parameter.", col.pos);
				}
			}
			
			//trace('===' + f.name);
			//trace(f.kind);
			
			// TODO: Allow fields with only a default value, no type
			var opt = switch f.kind {
				case FVar(TPath(p), _) if (p.name == "Null"): true;
				case FProp(_, _, TPath(p), _) if (p.name == "Null"): true;
				case _: false;
			}
			
			// If a default value exists, extract it from the field
			var def : Expr = switch f.kind {
				case FVar(p, e) if (e != null):
					f.kind = FVar(p, null);
					e;
				case FProp(get, set, p, e) if (e != null):
					f.kind = FProp(get, set, p, null);
					e;
				case _: 
					macro null;
			}
			
			// Make the field nullable if it has a default value but is not optional
			if (def.toString() != 'null' && !opt) {				
				switch def.expr {
					// Special case for js optional values: Date.now() will be transformed to this:
					case ECall( { expr: EConst(CIdent("__new__")), pos: _ }, [ { expr: EConst(CIdent("Date")), pos: _ }]):
						// Make it into its real value:
						def.expr = (macro Date.now()).expr;
					case _:
				}
				
				//Context.warning(f.name + ' type: ' + f.kind + ' default: ' + def.toString(), f.pos);
				opt = true;
				switch f.kind {
					case FVar(t, e): 
						var nullWrap = TPath({ name: 'Null', pack: [], params: [TPType(t)]});
						f.kind = FVar(nullWrap, e);
						//trace(f.name + " set to null");
					case FProp(get, set, t, e):
						var nullWrap = TPath({ name: 'Null', pack: [], params: [TPType(t)]});
						f.kind = FProp(get, set, nullWrap, e);
						//trace(f.name + " set to null");
					case _:						
				}
			}
			
			// Test Mithril property
			if (f.meta.exists(function(m) return m.name == "prop")) {
				switch f.kind {
					// Don't modify if it's already a GetterSetter.
					case FVar(TFunction([TOptional(_)], _), _), FProp(_, _, TFunction([TOptional(_)], _), _):
						
					case FVar(t, e):
						f.kind = FVar(TFunction([TOptional(t)], t), e);
					
					case FProp(get, set, t, e):
						f.kind = FProp(get, set, TFunction([TOptional(t)], t), e);
						
					case _:
				}
				
 				switch def {
					// Don't create a M.prop if it's not already one
					case macro M.prop($e), macro mithril.M.prop($e):
						
					case _: 
						def = {expr: (macro mithril.M.prop($def)).expr, pos: def.pos};
				}
			}

			function createValidator(e : Expr) : Expr {
				var test : Expr;
				var name = f.name;
				var clsName = cls.name;				
				
				function replaceParam(e : Expr) return switch e.expr { 
					case EConst(CIdent("_")): macro this.$name;
					case _: e.map(replaceParam);
				}
				
				switch e.expr {
					case EConst(CRegexp(r, opt)):
						if (!r.startsWith('^') && !r.endsWith('$')) r = '^' + r + "$";
						test = macro new EReg($v{r}, $v{opt}).match(this.$name);
					case _: 
						test = replaceParam(e);
				}
				
				e.expr = EConst(CString(e.toString()));
				
				var errorString = macro "Field " + $v{clsName} + "." + $v{name} + ' failed validation "' + $e + '" with value "' + this.$name + '"';
				var throwType = throwError(errorString);
				
				return nullTestAllowed(f)
					? macro if ((!$v{opt} || this.$name != null) && !$test) $throwType
					: macro if (!$v{opt} && !$test) $throwType;
			}
			
			var validator = f.meta.find(function(m) return m.name == "validate");
			
			fieldMap.set(f, {
				opt: opt, 
				def: def, 
				val: validator == null ? null : createValidator(validator.params[0]),
			});

			if(opt) f.meta.push({
				pos: cls.pos,
				params: [],
				name: ':optional'
			});
		}
		
		var assignments = [];
		
		for (f in publicFields) {
			var data = fieldMap.get(f);
			var def = data.def;
			var opt = data.opt;
			var val = data.val;
			var name = f.name;
			var clsName = cls.name;
			
			var assignment = opt
				? macro data.$name != null ? data.$name : $def
				: macro data.$name;
			
			switch f.kind {
				case FVar(TPath(p), _) | FProp(_, _, TPath(p), _):
					var typeName = switch p {
						case { name: "Null", pack: _, params: [TPType(TPath( { name: n, pack: _, params: _ } ))] } :
							n;
						case _:
							p.name;
					};
					
					if (Converter.DynamicObjectConverter.supportedTypes.has(typeName)) {
						f.meta.push({
							pos: f.pos,
							params: [{expr: EConst(CString(typeName)), pos: f.pos}],
							name: "convertTo"
						});
					}
				case _:
			}
			
			assignments.push(macro this.$name = $assignment);
					
			if (!opt && nullTestAllowed(f)) {
				var throwStatement = throwError(macro "Field " + $v { clsName } + "." + $v { name } + " was null.");				
				assignments.push(macro if (this.$name == null) $throwStatement);
			}
			
			if (val != null) assignments.push(val);
		};
		
		var constructor = fields.find(function(f) return f.name == "new");
		
		if (constructor == null) {
			var allOptional = ![for (f in fieldMap) f].exists(function(f) return f.opt == false);
			
			// Call parent constructor if it exists
			if (cls.superClass != null)	assignments.unshift(macro super(data));
			
			// If all fields are optional, create a default argument assignment
			if (allOptional) assignments.unshift(macro if (data == null) data = {});
				
			fields.push({
				pos: cls.pos,
				name: 'new',
				meta: [],
				kind: FFun({
					ret: null,
					params: [],
					expr: {expr: EBlock(assignments), pos: cls.pos},
					args: [{
						value: null,
						type: TAnonymous(publicFields),
						opt: allOptional,
						name: 'data'
					}]
				}),
				doc: null,
				access: [APublic]
			});
		} else {
			switch constructor.kind {
				case FFun(f):
					switch f.expr.expr {
						case EBlock(exprs): f.expr.expr = EBlock(assignments.concat(exprs));
						case _: f.expr.expr = EBlock(assignments.concat([f.expr]));
					}
				case _: 
					Context.error("Invalid constructor.", constructor.pos);
			}
		}

		return fields;	
	}
	
	////////////////////////////////////////////////////////////////////////////////
	
	static function ignored(f : Field) {
		return !f.meta.exists(function(m) return m.name == "ignore");
	}

	static function publicVarOrProp(f : Field) {
		if(f.access.has(AStatic) || !f.access.has(APublic)) return false;
		return switch(f.kind) {
			case FVar(_, _): true;
			case FProp(_, set, _, _): set == "default" || set == "null" || set == "set";
			case _: false;
		}
	}

	static function typedefKind(kind : FieldType, pos : Position) : FieldType {
		// A superfluous method it seems, but having some problem with 
		// FieldType/FieldKind confusion unless done like this.
		return switch kind {
			case FProp(_, _, t, e): FVar(t, e);
			case FVar(_, _): kind;
			case _: Context.error("Invalid field type for DataClass, should not be allowed here.", pos);
		}		
	}
	
	static function fieldToTypedefField(c : Field) : Field {	
		return {
			pos: c.pos,
			name: c.name,
			meta: c.meta,
			kind: typedefKind(c.kind, c.pos),
			doc: c.doc,
			access: [APublic]
		};
	}

	static function classFieldToField(c : ClassField) : Field {
		var typedExpr = c.expr();
		return {
			pos: c.pos,
			name: c.name,
			meta: c.meta.get(),
			kind: FVar(Context.toComplexType(c.type), typedExpr != null ? Context.getTypedExpr(typedExpr) : null),
			doc: c.doc,
			access: c.isPublic ? [APublic] : []
		};
	}
	
	static function childAndParentFields(fields : Array<Field>, cls : ClassType) : Array<Field> {
		var typeFields = fields.filter(ignored).filter(publicVarOrProp).map(fieldToTypedefField);

		if(cls.superClass == null) return typeFields;

		var superClass = cls.superClass.t.get();
		return childAndParentFields(superClass.fields.get().map(classFieldToField), superClass).concat(typeFields);
	}
}
#end