package dataclass.macros;

#if macro
import haxe.DynamicAccess;
import haxe.macro.ComplexTypeTools;
import haxe.macro.MacroStringTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.ds.Option;

using haxe.macro.ExprTools;
using haxe.macro.MacroStringTools;
using Lambda;
using StringTools;

private enum Nullability {
	None(validators: Array<Expr>);
	Nullable(validators: Array<Expr>);
	DefaultValue(validators: Array<Expr>);
}

private typedef DataClassField = {
	field: Field,
	nullability: Nullability,
	isOption: Bool
}

@:forward(name, pos, meta, pack)
private abstract DataClassType(ClassType) from ClassType
{
	public function new(cls : ClassType) {
		this = cls;
	}

	function superClasses() : Array<ClassType> {
		final output = [];
		
		function getSuper(sc) return sc == null ? null : sc.t.get();
		var superClass = getSuper(this.superClass);
			
		while (superClass != null) {
			output.push(superClass);
			superClass = getSuper(superClass.superClass);
		}
		
		return output;
	}
	
	public function superclassFields() : Array<Field> {
		if(this.superClass == null) return [];

		function isClassFieldDataClassField(classField : ClassField) : Bool { return
			classField.kind != null &&
			(!classField.meta.has('exclude') || classField.meta.has('include'));
		}
		
		final classFields = superClasses().flatMap(function(superClass) 
			return superClass.fields.get().filter(isClassFieldDataClassField)
		);

		return classFields.map(f -> {
			access: f.isPublic ? [APublic, AFinal] : [AFinal],
			doc: f.doc,
			kind: switch f.kind {
				case FVar(read, write):
					if(read != AccNormal || write != AccCtor)
						Context.error("Only final fields can be a part of DataClass inheritance.", f.pos);

					FieldType.FVar(
						Context.toComplexType(f.type), 
						f.expr() == null ? null : Context.getTypedExpr(f.expr())
					);
				case _:
					null;
			},
			meta: f.meta.get(),
			name: f.name,
			pos: f.pos
		}).filter(f -> f.kind != null);
	}	
	
	function implementsInterface(interfaceName : String) {
		return this.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == interfaceName;
		});
	}
}

// ============================================================================

class Builder2
{
	//
	// Macro entry point
	//
	static public function build() : Array<Field> {
		#if (haxe_ver < 4)
		Context.error("DataClass requires Haxe 4.", cls.pos);
		#end

		final cls : ClassType = Context.getLocalClass().get();

		if (cls.isInterface) return null;		
		if (cls.meta.has(":dataClassGenerated")) return null;
		else cls.meta.add(":dataClassGenerated", [], cls.pos);

		// Add validators from interfaces
		final interfaceFields = [for(i in cls.interfaces) {
			var interf = i.t.get();
			for(f in interf.fields.get()) if(f.meta.has(':validate')) 
				f.name => f.meta.extract(':validate').map(m -> m.params[0]);
		}];

		function toDataClassField(f : Field) : DataClassField {
			final isOption = switch f.kind {
				case FFun(func): return null;
				case FVar(t, e) if(f.access != null && f.access.has(AFinal)): 
					switch t {
						case TPath(p) if(p.name == "Option"):
							// TODO: Move modification to last step before returning fields
							if(e == null) f.kind = FVar(t, macro haxe.ds.Option.None)
							else f.kind = FVar(t, macro haxe.ds.Option.Some($e));
							true;
						case _:
							false;
					}
				case _: 
					Context.error("Variable fields and properties are not allowed in a DataClass. Use final instead.", f.pos);
			}

			var validators = if(f.meta == null) [] 
			else f.meta.filter(f -> f.name == "validate" || f.name == ":validate").map(f -> f.params[0]);
			
			if(interfaceFields.exists(f.name))
				validators = validators.concat(interfaceFields.get(f.name));

			final nullability = switch f.kind {
				case FVar(TPath({name: "Null", pack: [], params: _, sub: _}), e):
					if(e != null) Context.error(
						"A DataClass field cannot be nullable and have a default value.", f.pos
					);
					//trace(f.name + " is nullable");
					Nullable(validators);
				case FVar(t, e) if(e != null):
					//trace(f.name + " has default value");
					DefaultValue(validators);
				case _:
					//trace(f.name + " is neither nullable nor has default value.");
					None(validators);
			}

			return {
				field: f,
				nullability: nullability,
				isOption: false
			}
		}

		final allFields = Context.getBuildFields();
		final dataclassFields = allFields.map(toDataClassField).filter(f -> f != null);
		final superclassFields = new DataClassType(cls).superclassFields();
		final constructorFields = superclassFields.map(toDataClassField).concat(dataclassFields);

		var allOptional = true;
		final constructorTypedef = constructorFields.map(f -> {
			access: f.field.access,
			doc: f.field.doc,
			kind: switch f.field.kind {
				case FVar(t, _):
					FieldType.FVar(t, null);
				case _:
					Context.error("Variable fields and properties are not allowed in a DataClass. Use final instead.", f.field.pos);
			},
			meta: switch f.nullability {
				case None(_): 
					allOptional = false;
					f.field.meta;
				case _:
					f.field.meta.concat([{
						name: ":optional",
						pos: f.field.pos
					}]);
			},
			name: f.field.name,
			pos: f.field.pos
		});

		///// - Generate static validate function

		final validateBoilerplate = [
			(macro var errors : DataClassErrors = null, hasErrors = false),

			(macro function setError(field, value) {
				if(errors == null) errors = new DataClassErrors();
				errors.set(field, value);
				hasErrors = true;
			}),
		];

		/*
		Any field that (can be null or has default value) and (has no validator) is not tested.
		Default and Nullable cannot be combined.

        Default | Nullable | Validator | TEST
		        |          |           |  (1)
		        |     x    |     x     |  (2)
		        |          |     x     |  (3)
		   x    |          |     x     |  (4)
		   x    |     x    |     x     |  N/A
		   x    |     x    |           |  N/A
		   x    |          |           |  (7)
		        |     x    |           |  (8)
		*/

		/*
		       | Expression | Regexp |
		-------------------------------------		
		Normal | if(!E)     | if(!R.match(Std.string(field)))
		Option | switch     | 
		*/

		function validatorExpr(f : DataClassField, e : Expr) {
			return switch e.expr {
				case EConst(CIdent("_")):
					// "v" var
					macro v;
				case _:
					e.map(validatorExpr.bind(f));
			}
		}

		function replaceValidators(vals : Array<Expr>, f : DataClassField) {
			// TODO: Check if validators exist
			final newVals = vals.map(validatorExpr.bind(f));
			final it = newVals.iterator();

			function orOp(current : Expr) : Expr {
				switch current.expr {
					case EConst(CRegexp(r, opt)):
						current = macro ${current}.match(Std.string(v));
					case _:
				}
				return if(!it.hasNext()) macro !$current;
				else macro !$current || ${orOp(it.next())}
			}

			return orOp(it.next());
		}

		function actualValue(f : DataClassField) : Expr {
			return if(f.isOption)
				macro switch $p{['data', f.field.name]} {
					case None: null;
					case Some(v): v;
				}
			else
				macro $p{['data', f.field.name]};
		}

		function replace(f : DataClassField, validators : Array<Expr>) : Expr {
			// "v" var
			return macro {
				final v = ${actualValue(f)};
				if(${replaceValidators(validators, f)})
					setError($v{f.field.name}, haxe.ds.Option.Some(v));
			}
		}

		for(f in dataclassFields) {
			var name = f.field.name;
			switch f.nullability {
				/*(1)*/	case None(validators) if(validators.length == 0):
					validateBoilerplate.push(macro 
						if($p{['data', name]} == null) 
							setError($v{name}, haxe.ds.Option.None)
					);

				/*(3)*/ case None(validators):
					validateBoilerplate.push(macro 
						if($p{['data', name]} == null) 
							setError($v{name}, haxe.ds.Option.None)
						else
							${replace(f, validators)}
					);

				/*(8)*/ case Nullable(validators) if(validators.length == 0):

				/*(2)*/ case Nullable(validators):
					validateBoilerplate.push(macro 
						${replace(f, validators)}
					);

				/*(7)*/ case DefaultValue(validators) if(validators.length == 0):

				/*(4)*/ case DefaultValue(validators):
					validateBoilerplate.push(macro 
						if($p{['data', name]} == null) 
							null
						else 
							${replace(f, validators)}
					);

				case _:
					Context.error("Invalid default/nullable state for field.", f.field.pos);
			}
		}

		validateBoilerplate.push(macro return hasErrors 
			? haxe.ds.Option.Some(errors) 
			: haxe.ds.Option.None
		);

		final validateFunction = {
			access: [APublic, AStatic],
			kind: FFun({
				args: [{
					name: 'data',
					opt: false,
					type: TAnonymous(constructorTypedef)
				}],
				expr: macro $b{validateBoilerplate},
				ret: macro : haxe.ds.Option<DataClassErrors>
			}),
			name: 'validate',
			pos: cls.pos
		}

		///// - Generate constructor

		final constructorFunction : Array<Expr> = [for(f in dataclassFields) {
			// if(data.field != null) this.field = data.field
			macro if($p{['data', f.field.name]} != null) $p{['this', f.field.name]} = $p{['data', f.field.name]};
		}];

		constructorFunction.unshift(macro switch validate(data) { 
			case Some(errors): throw errors; 
			case None: 
		});

		if(allOptional)
			constructorFunction.unshift(macro if(data == null) data = {});

		if(cls.superClass != null)
			constructorFunction.push(macro super(cast data));

		final constructor = {
			access: [APublic],
			kind: FFun({
				args: [{
					name: 'data',
					opt: allOptional,
					type: TAnonymous(constructorTypedef)					
				}],
				expr: macro $b{constructorFunction},
				ret: null
			}),
			name: 'new',
			pos: cls.pos
		}

		for(f in allFields) {
			// Remove validation metadata for backwards compatibility
			f.meta = f.meta.filter(f -> f.name != "validate");
		}

		return allFields.concat([constructor, validateFunction]);
	}
	

	///////////////////////////////////////////////////////////////////////////

	function failedValidationThrowExpr(message : String, arg : Expr) {
		return if (Context.defined("dataclass-throw")) {
			var throwClass = Context.definedValue("dataclass-throw").split(".");
			var newCustomClass = { expr: 
				ENew({
					name: throwClass[throwClass.length - 1],
					pack: throwClass.slice(0, throwClass.length - 1),
					params: null,
					sub: null
				}, [macro $v{message}, macro this, macro $arg])
			, pos: Context.currentPos()
			};
			
			macro throw $newCustomClass;
		}
		else {
			macro throw $v{message};
		}
	}
	
	///////////////////////////////////////////////////////////////////////////
			
	/*
	function createDataClassFields() : Array<Field> {
		//trace("======= " + CLASS.name);
		
		// As a last step, need to remove @validate from superclass fields, otherwise their Expr won't compile.
		for (superClassField in CLASS.superClasses().flatMap(function(f) return f.fields.get())) {
			superClassField.meta.remove('validate');
		}
		
		var normalFieldsWithoutConstructor = OTHERFIELDS.filter(function(f) return f.name != 'new');
				
		//for (f in newDataClassFields) trace(f.name + " -> " + f.kind);
		
		return normalFieldsWithoutConstructor
			.concat([createStaticValidateMethod(), createConstructor()])
			.concat(newDataClassFields)
			.concat(newSetters)
			.filter(function(f) return f != null);
	}
	*/
	
	///////////////////////////////////////////////////////////////////////////
	
	/*
	function createStaticValidateMethod() : Null<Field> {
		var argName = 'data';
		var validationTests = dataClassFieldsIncludingSuperFields.map(function(f) {
			var testFieldAccessor = macro $p{[argName, f.name]};
			var fieldExists = macro Reflect.hasField($i{argName}, $v{f.name});
			var addToOutput = macro output.push($v { f.name } );
			
			// Important distinction between validation in the setter:
			// If input doesn't exist and field is optional, validation will still succeed.
			// This means that the test should be if the field is optional, not if it can be null.
			var canBeNull = macro $v{f.isOptional()};
			
			var testExpr = switch Validator.createValidatorTestExpr(f.type(), testFieldAccessor, 
				f.isOptional(), f.validation) 
			{
				case None: macro false;
				case Some(e): e;
			}
			
			return macro {
				if (!$canBeNull && !$fieldExists) $addToOutput
				else if ($testExpr) $addToOutput;
			}
		});
		
		return {
			access: [APublic, AStatic],
			doc: null,
			kind: FFun({
				args: [{
					meta: null,
					name: 'data',
					opt: false,
					type: null, //assignmentAnonymousType([], true),
					value: null
				}],
				expr: macro { var output = []; $b{validationTests}; return output; },
				params: null,
				ret: macro : Array<String>
			}),
			meta: null,
			name: 'validate',
			pos: CLASS.pos
		}
	}
	*/
	
	///////////////////////////////////////////////////////////////////////////
	
	/*
	function createConstructor() {
		// Returns all field assignments based on the first constructor parameter.
		// "this.name = data.name"
		function constructorAssignments(varName : String) : Expr {
			var assignments = dataClassFieldsIncludingSuperFields.filter(function(f) {
				var access = f.setAccess(CLASS.isImmutable());
				// Allow constructor assignment if the field is final.
				return f.isFinal() || access != 'never';
			})
			.map(function(f : DataField) {
				var assignment = macro $p{['this', f.name]} = $p{[varName, f.name]};

				// If immutable or final, validate data in constructor since no setter exists.
				if(CLASS.isImmutable() || f.isFinal()) {					
					var errorMsg = "DataClass validation failed for " + CLASS.name + "." + f.name + ".";
					var identifier = macro $p{[varName, f.name]};
					var validationTestExpr = createValidationTestExpr(f, identifier, failedValidationThrowExpr(errorMsg, identifier));

					assignment = switch(validationTestExpr.expr) {
						case EIf(econd, eif, eelse):
							{expr: EIf(econd, eif, assignment), pos: assignment.pos};
						case EConst(CIdent("null")):
							assignment;
						default:
							throw "Invalid test expr, must be EIf.";
					};
				}

				return f.isOptional()
					? (macro if(Reflect.hasField($i{varName}, $v{f.name})) $assignment)
					: assignment;
			});
			
			//trace(assignments.map(function(a) return a.toString()).join(";\n"));
			
			var block = areAllDataClassFieldsOptional()
				? (macro if ($i{varName} != null) $b{assignments}) 
				: macro $b{assignments};
			
				
			return block;
		}
		
		var existing : Field = OTHERFIELDS.find(function(f) return f.name == 'new');
		
		var arguments : Array<FunctionArg> = if (existing != null) {
			switch existing.kind {
				case FFun(f):
					function error(str) Context.error(str, f.expr.pos);
					
					var parameterFields : Array<DataField> = [];
					
					// Testing for a correct constructor definition
					if (f.args.length == 0) {
						error("The DataClass constructor must have at least one parameter.");
					}
					else if (f.args[0].type != null) {
						switch f.args[0].type {
							case TAnonymous(fields):
								parameterFields = fields.map(function(f) return DataField.fromField(f));
							case _:
								error("The first parameter in a DataClass constructor must be empty or an anonymous structure.");
						}
					} else if (areAllDataClassFieldsOptional() && (f.args[0].opt == null || !f.args[0].opt)) {
						error("All DataClass fields are optional, so the first constructor parameter must also be optional.");
					} else if (f.args[0].value != null) {
						error("The first parameter in a DataClass constructor cannot have a default value.");
					}
					
					for (arg in f.args.slice(1)) {
						if ((arg.opt == null || arg.opt == false) && arg.value == null) {
							error("All subsequent constructor parameters in a DataClass must be optional");
						}
					}
					
					// Set type for first argument, and return the args structure
					// TODO: Code completion doesn't work for the constructor parameter
					f.args[0].type = assignmentAnonymousType(parameterFields);
					
					var assignments = constructorAssignments(f.args[0].name);
					switch(f.expr.expr) {
						case EBlock(exprs): exprs.unshift(assignments);
						case _: f.expr = {
							pos: f.expr.pos,
							expr: EBlock([assignments, f.expr])
						}
					}
					
					f.args;
				case _:
					Context.error("Invalid constructor", existing.pos);
			}
		} else [{
			meta: null,
			name: 'data',
			opt: areAllDataClassFieldsOptional(),
			type: assignmentAnonymousType([]),
			value: null
		}];
		
		var newConstructor = {
			access: if (existing != null) existing.access else [APublic],
			doc: if (existing != null) existing.doc else null,
			kind: if(existing != null) existing.kind else FFun({
				args: arguments,
				expr: constructorAssignments(arguments[0].name),
				params: [],
				ret: macro : Void
			}),
			meta: if (existing != null) existing.meta else null,
			name: 'new',
			pos: CLASS.pos
		};
		
		return newConstructor;
	}
	*/
	
	///////////////////////////////////////////////////////////////////////////
	
	// Returns a type used for the parameter to the constructor.
	// the allOptional parameter is used for the static "validate" method, so any object can be used.
	/*
	function assignmentAnonymousType(extraFields : Array<DataField>, allOptional = false) : ComplexType {
		var fields = dataClassFieldsIncludingSuperFields.concat(extraFields)
		.map(function(f) return {
			pos: f.pos,
			name: f.name,
			meta: if(allOptional || f.isOptional()) [{
				pos: f.pos,
				params: null,
				name: ":optional"
			}] else null,
			kind: FieldType.FVar(f.type(), null),
			doc: null,
			access: []
		});
		
		return TAnonymous(fields);
	}
	*/
}

// ============================================================================

private class Validator
{
	static var illegalNullTypes = ['Int', 'Float', 'Bool'];
	
	static var isStaticPlatform = Context.defined("cpp") || Context.defined("java") || 
		Context.defined("flash") || Context.defined("cs") || Context.defined("hl");
	
	// Testing for null is only allowed if on a non-static platform or the type is not a basic type.
	public static function nullTestAllowed(type : ComplexType) : Bool {
		if (!isStaticPlatform) return true;
		
		return switch Context.followWithAbstracts(ComplexTypeTools.toType(type)) {
			case TAbstract(t, _):
				var type = MacroStringTools.toDotPath(t.get().pack, t.get().name);
				return !illegalNullTypes.has(type);
			case _: true;
		}
	}
	
	// Returns an Expr that, if true, should fail validation.
	public static function createValidatorTestExpr(
		type : ComplexType, field : Expr, canBeNull : Bool, validators : Array<Expr>) : Option<Expr> {

		// TODO: Support more than one validator
		if (validators.length > 1) 
			Context.error("Currently only one @validate() is supported per field", validators[1].pos);
		
		var cannotBeNull = !canBeNull && nullTestAllowed(type);
		
		/*
		If the type is an Option, return an expression that tests the unwrapped value,
		otherwise just the original expression.
		*/ 
		var validatorTests = validators.map(function(validator) {
			function replaceParam(field : Expr, e : Expr) return switch e.expr { 
				case EConst(CIdent("_")): macro $field;
				case _: e.map(replaceParam.bind(field));
			}

			var isOption = switch type {
				case TPath(p) if(p.name == "Option"): true;
				case _: false;
			}

			return switch validator.expr {
				case EConst(CRegexp(r, opt)):
					if (!r.startsWith('^') && !r.endsWith('$')) r = '^' + r + "$";
					if(isOption)
						macro switch ($field) { case None: false; case Some(v): new EReg($v{r}, $v{opt}).match(v); }
					else
						macro new EReg($v{r}, $v{opt}).match($field);
				case _:
					if(isOption)
						replaceParam(
							macro v,
							macro switch ($field) { case None: null; case Some(v): $validator; }
						)
					else
						replaceParam(field, validator);
			}
		});

		var testExpr = if(nullTestAllowed(type)) {
			if (validatorTests.length == 0 && !canBeNull) {
				macro $field == null;
			} else if (validatorTests.length > 0) {
				var test = validatorTests[0];
				if (!canBeNull) macro $field == null || !($test);
				else macro $field != null && !($test);
			} else {
				null;
			}
		} else {
			if (validatorTests.length > 0) {
				var test = validatorTests[0];
				macro !($test);
			} else {
				null;
			}
		}
		
		//trace(testExpr.toString());
		return testExpr == null ? Option.None : Option.Some(testExpr);
	}
}
#end
