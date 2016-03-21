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
		
		// Fields aren't available on Context.getLocalClass().
		// need to supply them here. They're available on the superclass though.
		var publicFields = publicFields(fields, cls);
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
				case FProp(get, set, t, e): f.kind = FProp(get, set == 'never' ? 'never' : 'null', t, e);
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
			var optional = switch f.kind {
				case FVar(TPath(p), _) if (p.name == "Null"): true;
				case FProp(_, _, TPath(p), _) if (p.name == "Null"): true;
				case _: false;
			}
			
			// If a default value exists, extract it from the field
			var defaultValue : Expr = switch f.kind {
				case FVar(p, e) if (e != null): e;
				case FProp(get, set, p, e) if (e != null): e;
				case _: macro null;
			}
			
			// Make the field nullable if it has a default value but is not optional
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
				/*
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
				*/
			}
			
			/*
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
				
 				switch defaultValue {
					// Don't create a M.prop if it's not already one
					case macro M.prop($e), macro mithril.M.prop($e):
						
					case _: 
						defaultValue = {expr: (macro mithril.M.prop($defaultValue)).expr, pos: defaultValue.pos};
				}
			}
			*/

			var validator = f.meta.find(function(m) return m.name == "validate");
			
			fieldMap.set(f, {
				optional: optional, 
				defaultValue: defaultValue, 
				validator: validator == null ? null : validator.params[0]
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
		
		for (f in publicFields) {
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

			function validationExpr(param : String, e : Null<Expr>) : Array<Expr> {
				if (e == null) e = {expr: EBlock([]), pos: f.pos};
				switch e.expr {
					case EBlock(exprs):
						var assignments = [];
						if(exprs.length == 0) assignments.push(macro this.$name = $i{param});
						
						//assignments.push(macro trace("setting value to " + $i { param } ));
								
						if (!optional && nullTestAllowed(f)) {
							var throwStatement = throwError(macro "Field " + $v{clsName} + "." + $v{name} + " was null.");				
							assignments.push(macro if ($i{param} == null) $throwStatement);
						}
						
						if (validator != null) assignments.push(createValidator(param, validator));
						if (exprs.length == 0) assignments.push(macro return this.$name);
						
						//for (a in assignments) trace(a.toString());
						
						return assignments.concat(exprs);
						
					case _: return validationExpr(param, {expr: EBlock([e]), pos: e.pos});
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
						expr: {expr: EBlock(validationExpr(name, null)), pos: f.pos}
					}),
					doc: null,
					access: [APrivate]
				});
				
				//var test = macro : { ?test : Int }; trace(test);

				/*
				var anonType : ComplexType = type;
				if (optional) switch type {
					case TPath(p): 
						trace("making " + f.name + " optional");
						var nullWrap = TPath({ name: 'Null', pack: [], params: [TPType(type)]});
						type = nullWrap;
					case _:
				}
				*/				
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

			// Transform to a setter
			switch f.kind {
				case FVar(type, _):
					createValidationSetter("default", type);
					createAnonymousValidationField(type);

				// If a property setter already exists, inject validation into the beginning of it.
				case FProp(get, set, type, e) if (set == "set"):				
					var accessorField = fields.find(function(f2) return f2.name == "set_" + f.name);
					switch accessorField.kind {
						case FFun(f2):
							f2.expr.expr = EBlock(validationExpr(f2.args[0].name, f2.expr));
						case _:
							Context.error("Invalid setter accessor", accessorField.pos);
					}
					createAnonymousValidationField(type);
					
				case FProp(get, _, type, _):
					// If property has a getter, it will be non-physical by default.
					// Add :isVar metadata to tell the compiler to create a physical field.
					// see http://haxe.org/manual/class-field-property-rules.html
					if (get == "get") {
						f.meta.push({
							pos: f.pos, params: null, name: ":isVar"
						});
					}
					
					createValidationSetter(get, type);
					createAnonymousValidationField(type);
					
				case FFun(_):
			}
			
			// Add to assignment in constructor
			assignments.push(macro this.$name = $assignment);
		};

		if (!cls.isInterface) {
			var constructor = fields.find(function(f) return f.name == "new");

			if (constructor == null) {

				// Call parent constructor if it exists
				//if (cls.superClass != null)	assignments.unshift(macro super(data));

				// If all fields are optional, create a default argument assignment
				if (allOptional) assignments.unshift(macro if (data == null) data = {});
				
				//for (a in assignments) trace(a.toString());
				
				/*
				var constructorContent = allOptional
					? (macro if(data != null) $b{assignments}).expr
					: (macro $b{assignments}).expr;
				*/				
				
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
						switch f.expr.expr {
							case EBlock(exprs): f.expr.expr = EBlock(assignments.concat(exprs));
							case _: f.expr.expr = EBlock(assignments.concat([f.expr]));
						}
					case _:
						Context.error("Invalid constructor.", constructor.pos);
				}
			}
		}
		
		return fields.concat(validationFields);	
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
			case FProp(get, set, t, e): FProp(get, set, t, e);
			case FVar(_, _): kind;
			case _: Context.error("Invalid field type for DataClass, should not be allowed here.", pos);
		}		
	}
	
	/*
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
	*/
	
	static function publicFields(fields : Array<Field>, cls : ClassType) : Array<Field> {
		return fields.filter(ignored).filter(publicVarOrProp);// .map(fieldToTypedefField);

		/*
		if(cls.superClass == null) return typeFields;

		var superClass = cls.superClass.t.get();
		return childAndParentFields(superClass.fields.get().map(classFieldToField), superClass).concat(typeFields);
		*/
	}
}
#end