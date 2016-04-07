package dataclass.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using Lambda;
using StringTools;

private typedef FieldDataProperties = {
	optional: Bool, 
	defaultValue: Expr, 
	validator: Expr
}

class Builder
{
	static public function build() : Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass().get();
		var immutable = cls.meta.has("immutable");
		
		// Fields aren't available on Context.getLocalClass().
		// need to supply them here. They're available on the superclass though.
		var dataClassFields = includedFields(fields, cls);
		var fieldMap = new Map<Field, FieldDataProperties>();
		
		// Test if class implements HaxeContracts, then throw ContractException instead.
		var haxeContracts = cls.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == "HaxeContracts";
		});

		// Complications: Testing for null is only allowed if on a non-static platform or the type is not a basic type.
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

		for (f in dataClassFields) {
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
			var optional = switch f.kind {
				case FVar(TPath(p), _) if (p.name == "Null"): true;
				case FProp(_, _, TPath(p), _) if (p.name == "Null"): true;
				case _: false;
			}
			
			var fieldType : ComplexType = switch f.kind {
				case FVar(t, _): t;
				case FProp(_, _, t, _): t;
				case _: null;
			}
			
			// If a default value exists, extract it from the field
			var defaultValue : Expr = switch f.kind {
				case FVar(t, e) if (e != null): e;
				case FProp(get, set, t, e) if (e != null): e;
				case _: macro null;
			}
			
			// Make the field optional if it has a default value
			if (defaultValue.toString() != 'null' && !optional) {				
				switch defaultValue.expr {
					// Special case for js optional values: Date.now() will be transformed to this:
					case ECall( { expr: EConst(CIdent("__new__")), pos: _ }, [ { expr: EConst(CIdent("Date")), pos: _ }]):
						// Make it into its real value:
						defaultValue.expr = (macro Date.now()).expr;
					case _:
				}
				
				//Context.warning(f.name + ' type: ' + f.kind + ' default: ' + defaultValue.toString(), f.pos);
				optional = true;
			}

			// If field has no type, try to extract it from the default value, if it exists
			if (optional && fieldType == null) {
				try {
					var typed = Context.typeExpr(defaultValue);
					var type = Context.toComplexType(typed.t);
					
					switch f.kind {
						case FVar(_, e): f.kind = FVar(type, e);
						case FProp(get, set, _, e): f.kind = FProp(get, set, type, e);
						case _:
					}
				} catch (e : Dynamic) {
					// Let the compiler handle the error.
				}
			}
			
			var validatorMeta = f.meta.find(function(m) return m.name == "validate");
			var validator = validatorMeta == null ? null : validatorMeta.params[0];
			
			if (validatorMeta != null) {
				f.meta.remove(validatorMeta);
			}
			
			fieldMap.set(f, {
				optional: optional, 
				defaultValue: defaultValue, 
				validator: validator
			});

			if(optional) f.meta.push({
				pos: cls.pos,
				params: [],
				name: ':optional'
			});
		}
		
		///// Data is collected, now transform the fields /////
		
		var assignments = [];
		var validationFields = [];
		var anonymousValidationFields : Array<Field> = [];
		var allOptional = ![for (f in fieldMap) f].exists(function(f) return f.optional == false);
		
		for (f in dataClassFields) {
			var data = fieldMap.get(f);
			var defaultValue = data.defaultValue;
			var optional = data.optional;
			var validator = data.validator;
			var name = f.name;
			var clsName = cls.name;
			
			var assignment = optional
				? macro data.$name != null ? data.$name : $defaultValue
				: macro data.$name;
				
			// Create a new Expr to set the correct pos
			assignment = { expr: assignment.expr, pos: f.pos };
			
			// If the type can be converted using the DynamicObjectConverter, mark it with metadata
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

			function createValidator(paramName : String, e : Expr) : Expr {
				var test : Expr;
				var name = f.name;
				var clsName = cls.name;				
				
				function replaceParam(e : Expr) return switch e.expr { 
					case EConst(CIdent("_")): macro $i{paramName};
					case _: e.map(replaceParam);
				}
				
				switch e.expr {
					case EConst(CRegexp(r, optional)):
						if (!r.startsWith('^') && !r.endsWith('$')) r = '^' + r + "$";
						test = macro new EReg($v{r}, $v{optional}).match($i{paramName});
					case _: 
						test = replaceParam(e);
				}
				
				e.expr = EConst(CString(e.toString()));
				
				var errorString = macro "Field " + $v{clsName} + "." + $v{name} + ' failed validation "' + $e + '" with value "' + this.$name + '"';
				var throwType = throwError(errorString);
				
				return nullTestAllowed(f)
					? macro if ((!$v{optional} || $i{paramName} != null) && !$test) $throwType
					: macro if (!$v{optional} && !$test) $throwType;
			}

			function fieldAssignmentTests(param : String) : Array<Expr> {
				var assignments = [];

				if (!optional && nullTestAllowed(f)) {
					var throwStatement = throwError(macro "Field " + $v{clsName} + "." + $v{name} + " was null.");
					assignments.push(macro if ($i{param} == null) $throwStatement);
				}
				
				if (validator != null) assignments.push(createValidator(param, validator));

				return assignments;
			}

			function setterAssignmentExpressions(param : String, e : Null<Expr>) : Array<Expr> {
				if (e == null) e = {expr: EBlock([]), pos: f.pos};
				switch e.expr {
					case EBlock(exprs):
						var assignments = fieldAssignmentTests(param);						
						if (exprs.length == 0) assignments.push(macro return this.$name = $i{param});
						
						return assignments.concat(exprs);
						
					case _: 
						return setterAssignmentExpressions(param, {expr: EBlock([e]), pos: e.pos});
				}				
			}
			
			function createValidationSetter(getter : String, type : ComplexType) {
				f.kind = FProp(getter, "set", type, null);
				validationFields.push({
					pos: f.pos,
					name: "set_" + name,
					meta: null,
					kind: FFun({
						ret: type,
						params: null,
						args: [{
							value: null,
							type: type,
							opt: false,
							name: name
						}],
						expr: {expr: EBlock(setterAssignmentExpressions(name, null)), pos: f.pos}
					}),
					doc: null,
					access: [APrivate]
				});
			}

			function createAnonymousValidationField(type : ComplexType) {
				anonymousValidationFields.push({
					pos: f.pos,
					name: f.name,
					meta: if(optional) [{
						pos: f.pos,
						params: null,
						name: ":optional"
					}] else null,
					kind: FVar(type, null),
					doc: null,
					access: []
				});
			}

			switch f.kind {
				case FVar(type, e):
					if(!immutable)
						createValidationSetter("default", type);
					else
						f.kind = FProp('default', 'null', type, e);
						
					createAnonymousValidationField(type);

				// If a property setter already exists, inject validation into the beginning of it.
				case FProp(get, set, type, e) if (set == "set"):
					if (immutable) Context.error("Class is marked as immutable, cannot have setters.", f.pos);
					
					var accessorField = fields.find(function(f2) return f2.name == "set_" + f.name);
					switch accessorField.kind {
						case FFun(f2):
							f2.expr.expr = EBlock(setterAssignmentExpressions(f2.args[0].name, f2.expr));
						case _:
							Context.error("Invalid setter accessor", accessorField.pos);
					}
					createAnonymousValidationField(type);
					
				case FProp(_, set, type, _):
					if (immutable && set == "default") Context.error("Class is marked as immutable, cannot have setters.", f.pos);
					createAnonymousValidationField(type);
					
				case FFun(_):
			}
			
			// Add to assignment in constructor
			assignments.push(macro this.$name = $assignment);
		};

		if (!cls.isInterface) {
			var constructor = fields.find(function(f) return f.name == "new");

			if (constructor == null) {
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
							type: TAnonymous(anonymousValidationFields),
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
						// Set function argument "data" to the validation field
						if (f.args.length > 0 && f.args[0].name == "data" && f.args[0].type == null) {
							f.args[0].type = TAnonymous(anonymousValidationFields);
						}
						
						switch f.expr.expr {
							case EBlock(exprs): f.expr.expr = EBlock(assignments.concat(exprs));
							case _: f.expr.expr = EBlock(assignments.concat([f.expr]));
						}
					case _:
						Context.error("Invalid constructor.", constructor.pos);
				}
			}
		}
		
		if (immutable) {
			var replaceThis = ~/^this\./;
			var fieldNames = fields
				.filter(function(f) return dataClassFields.exists(function(pf) return pf.name == f.name))
				.map(function(f) return f.name);
			
			function preventAssign(e : Expr) switch e.expr {
				case EBinop(OpAssign, e1, _) if (fieldNames.has(replaceThis.replace(e1.toString(), ''))): 
					Context.error("Class " + cls.name + " is marked as immutable, cannot assign to any fields.", e.pos);
				case _: 
					e.iter(preventAssign);
			}
			
			for (f in fields) switch f.kind {
				case FFun(fun) if(f.name != 'new'): preventAssign(fun.expr);
				case _:
			}			
		}

		return fields.concat(validationFields);	
	}
	
	////////////////////////////////////////////////////////////////////////////////
	
	static function ignored(f : Field) {
		return !f.meta.exists(function(m) return m.name == "ignore" || m.name == "exclude");
	}

	static function publicVarOrPropOrIncluded(f : Field) {
		if (f.meta.exists(function(m) return m.name == "include")) return true;
		if (f.access.has(AStatic) || !f.access.has(APublic)) return false;
		return switch(f.kind) {
			case FVar(_, _): true;
			case FProp(_, set, _, _): set == "default" || set == "null" || set == "set";
			case _: false;
		}
	}

	static function includedFields(fields : Array<Field>, cls : ClassType) : Array<Field> {
		return fields.filter(ignored).filter(publicVarOrPropOrIncluded);
	}
}
#end