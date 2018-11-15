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

// ============================================================================

private typedef DataClassField = {
	> Field,
	var validation(default, null) : Array<Expr>;
}

// ============================================================================

@:forward(name, access, doc, meta, pos, validation, kind)
private abstract DataField(DataClassField) to Field
{
	inline function new(f : DataClassField) this = f;
	
	@:from static public function fromField(f : Field) {
		var val = f.meta.filter(function(m) return m.name == 'validate');
		/*
		if(val.length > 0) {
			Context.warning("Field " + f.name + ' has validation.', Context.currentPos());
			Context.warning(ExprTools.toString(val[0].params[0]), Context.currentPos());
		}
		*/
		return new DataField({
			access: f.access,
			doc: f.doc,
			kind: f.kind,
			meta: f.meta.filter(function(m) return m.name != 'validate'),
			name: f.name,
			pos: f.pos,
			validation: f.meta.filter(function(m) return m.name == 'validate').map(function(m) {
				if (m.params.length != 1) Context.error("@validate must have a single parameter", m.pos);
				return m.params[0];
			})
		});
	}

	public function isFinal() 
		#if (haxe_ver >= 4) 
		return this.access.has(AFinal);
		#else
		return false;
		#end
	
	public function isDataClassField() return
		isVarOrProp() &&
		!this.access.has(AStatic) &&
		!this.meta.exists(function(m) return m.name == 'exclude') &&
		(this.access.has(APublic) || this.meta.exists(function(m) return m.name == 'include'));

	// Test if the field is either Null<T> or has a default value.
	public function isOptional() return 
		canBeNull() || defaultValue() != null;
		
	// Returns the ComplexType of the var, or null if field isn't a var/prop.
	public function isVarOrProp() : Bool return switch this.kind {
		case FVar(t, _), FProp(_, _, t, _): true;
		case _: false;
	}

	// Returns the ComplexType of the var
	public function type() : Null<ComplexType> return switch this.kind {
		case FVar(t, _), FProp(_, _, t, _): t;
		case _: Context.error("A DataClass field cannot be a function", this.pos);
	}

	public function getAccess() : String return switch this.kind {
		case FVar(_, _): 'default';
		case FProp(get, _, _, _): get;
		case _: null;
	}

	public function setAccess(isImmutable : Bool) : String return switch this.kind {
		case FVar(_, _): isImmutable ? 'null' : 'default';
		case FProp(_, set, _, _): 
			if (isImmutable && set != 'null' && set != 'never')
				Context.error("A DataClass marked with @immutable cannot have writable setters.", this.pos);
			set;
		case _: null;
	}

	// Test if the field is Null<T>
	public function canBeNull() return switch type() {
		case TPath(p): p.name == "Null" || (p.name == "StdTypes" && p.sub == "Null");
		case _: false;
	}
	
	public function defaultValue() : Null<Expr> return switch this.kind {
		case FVar(_, e), FProp(_, _, _, e): 
			if(isOptionField()) {
				if(e == null) macro haxe.ds.Option.None
				else switch e.expr {
					case EConst(CIdent("null")):
						Context.error(
							"An Option field in a Dataclass cannot be set to null, it will be set to None automatically.", 
							e.pos
						);
					case _: macro haxe.ds.Option.Some($e);
				}
			} 
			else if(isDynamicAccessField() && e != null) switch e.expr {
				case EObjectDecl(fields):
					macro ($e : Dynamic);
				case _:
					Context.error("A DynamicAccess field must have an anonymous structure as a default value.", e.pos);
			}
			else e;

		case _: null;
	}

	public function isOptionField() return switch type() {
		case TPath(p) if(p.name == "Option"): true;
		case _: false;
	}

	public function isDynamicAccessField() return switch type() {
		case TPath(p) if(p.name == "DynamicAccess"): true;
		case _: false;
	}
}

// ============================================================================

@:forward(name, pos, meta, pack)
private abstract DataClassType(ClassType)
{
	public function new(cls : ClassType) {
		this = cls;

		// Assert that no parent class implements DataClass
		for (superClass in superClasses()) {
			if (superClass.interfaces.exists(function(i) return i.t.get().name == 'DataClass'))
				Context.error("A parent class cannot implement DataClass", superClass.pos);
		}
	}
	
	public function superClasses() : Array<ClassType> {
		var output = [];
		
		function getSuper(sc) return sc == null ? null : sc.t.get();
		var superClass = getSuper(this.superClass);
			
		while (superClass != null) {
			output.push(superClass);
			superClass = getSuper(superClass.superClass);
		}
		
		return output;
	}
	
	public function superclassFields() : Array<DataField> {
		function isClassFieldDataClassField(classField : ClassField) : Bool { return
			classField.kind != null &&
			!classField.meta.has('exclude') &&
			classField.isPublic || classField.meta.has('include');
		}
		
		var classFields = superClasses().flatMap(function(superClass) 
			return superClass.fields.get().filter(isClassFieldDataClassField)
		);
		
		return classFields.map(function(f) { 
			var fieldAccess = f.isPublic ? [APublic] : [];
			return {
				pos: f.pos,
				name: f.name,
				meta: f.meta.get(),
				kind: switch f.kind {
					case FVar(read, write):
						function toPropType(access : VarAccess, read : Bool) {
							//Context.warning(f.name + " " + Std.string(access), f.pos);
							return switch access {
								case AccNormal: 'default';
								case AccNo: 'null';
								case AccNever: 'never';
								#if (haxe_ver >= 4)
								case AccCtor: 
									// Field is final, add it to access.
									//for(m in f.meta.get()) Context.warning(m.name + ": " + ExprTools.toString(m.params[0]), Context.currentPos());
									fieldAccess.push(AFinal);
									'never';
								#end
								case AccCall: (read ? 'get_' : 'set_') + f.name; // Need to append accessor method
								case _: Context.error("Unsupported field for DataClass inheritance.", f.pos);
							}
						}
						var get = toPropType(read, true);
						var set = toPropType(write, false);
						
						var expr = f.expr() == null ? null : Context.getTypedExpr(f.expr());
						
						FProp(get, set, Context.toComplexType(f.type), expr);
					
					case _: null;
				},
				doc: f.doc,
				access: fieldAccess
			};
		}).map(function(f) return DataField.fromField(f)).array();
	}	
	
	public function isImmutable() return this.meta.has("immutable");
	
	public function shouldAddValidator() return !this.meta.has("noValidator");
		
	public function implementsInterface(interfaceName : String) {
		return this.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == interfaceName;
		});
	}
}

// ============================================================================

class Builder
{
	var CLASS(default, null) : DataClassType;
	var OTHERFIELDS(default, null) : Array<Field>;
	var DATACLASSFIELDS(default, null) : Array<DataField>;
	
	///////////////////////////////////////////////////////////////////////////
		
	//
	// Macro entry point
	//
	static public function build() : Array<Field> {
		var cls = Context.getLocalClass().get();
		if (cls.isInterface) return null;
		
		#if (haxe_ver < 3.3)
		Context.error("DataClass requires Haxe 3.3+", cls.pos);
		#end

		return new Builder().createDataClassFields();
	}
	
	///////////////////////////////////////////////////////////////////////////
	
	var dataClassFieldsIncludingSuperFields : Array<DataField>;

	function new() {		
		var allFields = Context.getBuildFields();

		CLASS = new DataClassType(Context.getLocalClass().get());		
		OTHERFIELDS = allFields.filter(function(f) return !DataField.fromField(f).isDataClassField());
		DATACLASSFIELDS = allFields
			.map(function(f) return DataField.fromField(f))
			.filter(function(f) return f.isDataClassField());

		dataClassFieldsIncludingSuperFields = CLASS.superclassFields().concat(DATACLASSFIELDS);
			
		//trace('Other: ' + OTHERFIELDS.map(function(f) return f.name));
		//trace('DataClassFields: ' + DATACLASSFIELDS.map(function(f) return f.name));
		
		if (CLASS.shouldAddValidator()) {
			var validateField = OTHERFIELDS.find(function(f) return f.name == "validate");
			if(validateField != null) {
				Context.error(
					"DataClass without @noValidator metadata cannot have a method called 'validate'"
				, validateField.pos);
			}
		}
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
		else if (Context.defined("dataclass-throw-js-error")) {
			macro throw new js.Error($v{message});
		}
		else {
			CLASS.implementsInterface("HaxeContracts")
				? macro throw new haxecontracts.ContractException($v{message}, this, $arg)
				: macro throw $v{message};
		}
	}
	
	///////////////////////////////////////////////////////////////////////////
			
	function areAllDataClassFieldsOptional() 
		return !dataClassFieldsIncludingSuperFields.exists(function(f) return !f.isOptional());
		
	///////////////////////////////////////////////////////////////////////////
			
	//
	// Entry point
	//
	function createDataClassFields() : Array<Field> {
		//trace("======= " + CLASS.name);
		
		var newSetters = [];

		function createNewSetter(field : DataField) {
			var fieldName = field.name;
			var argName = 'v';
			var errorMsg = "DataClass validation failed for " + CLASS.name + "." + field.name + ".";
			var identifier = macro $i{argName};
			var validationExpr = createValidationTestExpr(field, identifier, failedValidationThrowExpr(errorMsg, identifier));
			
			return {
				access: [],
				doc: null,
				kind: FFun({
					args: [{
						meta: null,
						name: argName,
						opt: false,
						type: field.type(),
						value: null
					}],
					expr: macro { $validationExpr; return this.$fieldName = v; },
					params: null,
					ret: field.type()
				}),
				meta: null,
				name: 'set_' + field.name,
				pos: field.pos
			}
		}
		
		var newDataClassFields = DATACLASSFIELDS.map(function(field) {
			var setAccess = field.setAccess(CLASS.isImmutable());

			//Context.warning(Std.string(CLASS.isFieldFinal(field.name)), field.pos);
			
			// Setters are used for validation, so create a setter if access is default
			if (setAccess == 'default' && !field.isFinal()) {
				newSetters.push(createNewSetter(field));
				setAccess = 'set';
			} else if (setAccess == 'set') {
				// If a setter already exists, inject validation into it
				var setterField = OTHERFIELDS.find(function(f) return f.name == 'set_' + field.name);
				if (setterField == null) Context.error("Missing setter for " + field.name, field.pos);
				
				var func = switch setterField.kind {
					case FFun(f): f;
					case _: Context.error("Invalid setter: not a method", setterField.pos);
				}
				
				if (func.expr == null) Context.error("Empty setter", setterField.pos);
				if (func.args.length != 1) Context.error("Invalid number of setter arguments", setterField.pos);

				var param = func.args[0];

				var errorMsg = "DataClass validation failed for " + CLASS.name + "." + field.name + ".";
				var identifier = macro $i{param.name};
				var validationTestExpr = createValidationTestExpr(field, identifier, failedValidationThrowExpr(errorMsg, identifier));
				
				switch func.expr.expr {
					case EBlock(exprs): exprs.unshift(validationTestExpr);
					case _: func.expr = {expr: EBlock([validationTestExpr, func.expr]), pos: func.expr.pos};
				}
			}
			
			return {
				access: field.access,
				doc: field.doc,
				kind: 
					if(field.isFinal()) field.kind
					else FProp(field.getAccess(), setAccess, field.type(), field.defaultValue()),
				meta: field.meta.filter(function(m) return m.name != 'validate'),
				name: field.name,
				pos: field.pos
			}
		});
		
		// Create rtti metadata
		var rttiMetadata = RttiBuilder.createMetadata(dataClassFieldsIncludingSuperFields);
		
		//trace('===== ' + CLASS.name); trace(rttiMetadata.map(function(f) return f.field + ": " + f.expr.toString()));

		CLASS.meta.add("dataClassRtti", [{expr: EObjectDecl(rttiMetadata), pos: CLASS.pos}], CLASS.pos);
		
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
	
	///////////////////////////////////////////////////////////////////////////
	
	function createValidationTestExpr(field : DataField, testField : Expr, failExpr : Expr) : Expr {
		// The validation test expression for the setter must test if the field can be null,
		// not if it's optional (has default value).
		var testExpr = Validator.createValidatorTestExpr(field.type(), testField, field.canBeNull(), field.validation);
		
		return switch testExpr {
			case None: macro null;
			case Some(testExpr): macro if ($testExpr) $failExpr;
		}
	}
	
	///////////////////////////////////////////////////////////////////////////
	
	function createStaticValidateMethod() : Null<Field> {
		if (!CLASS.shouldAddValidator()) 
			return null;
		
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
					type: assignmentAnonymousType([], true),
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
	
	///////////////////////////////////////////////////////////////////////////
	
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
	
	///////////////////////////////////////////////////////////////////////////
	
	// Returns a type used for the parameter to the constructor.
	// the allOptional parameter is used for the static "validate" method, so any object can be used.
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
}

// ============================================================================

private class RttiBuilder
{
	public static function createMetadata(dataClassFields : Array<DataField>) 
	{
		function typeAlias(t : Type, once = false) {
			return switch t {
				// Only if type is a typedef with no parameters, 
				// it can be used as an alias for a converter.
				case TType(t, params) if(params.length == 0): 
					var t2 = t.get();
					t2.pack.toDotPath(t2.name);

				// Haxe 3
				case TType(t, params): switch t.get().name {
					case "Null": typeAlias(params[0]);
					case "DynamicAccess"/*, "Any"*/: "Dynamic";
					case _: null;
				}

				// Haxe 4
				case TAbstract(t, params): switch t.get().name {
					case "Null": typeAlias(params[0]);
					// DynamicAccess and Any can be used as Dynamic
					case "DynamicAccess"/*, "Any"*/: "Dynamic";
					case _: 
						// Follow abstract types, in case they hide
						// another abstract type that is valid.
						// use once to prevent recursing infinite loops.
						if(once) null
						else typeAlias(Context.follow(t.get().type), true);
				}

				case TDynamic(null):
					"Dynamic";

				case _:
					null;
			}			
		}

		function fieldTypeToName(t : Type, field : DataField, alias : Null<String>) : String {
			function error(msg) {
				Context.error(msg, field.pos);
				return null;
			}
			
			return switch t {
				case TEnum(enumType, params):
					// Enums without constructors can be converted
					var e = enumType.get();
					var name = e.pack.toDotPath(e.name);

					// Special support for the Option<T> type
					if(name == 'haxe.ds.Option') {
						if(field.canBeNull()) error("Option fields cannot be nullable, they will be automatically set to None if no value is set.");
						var t = params[0];
						var alias = typeAlias(t);
						'Option<' + fieldTypeToName(t, field, alias) + '>';
					} else {
						for (c in e.constructs) switch c.type { 
							case TEnum(_, _):
							case _: error("Only Enums without constructors can be a DataClass field.");
						}
						'Enum<$name>';
					}
				case TAbstract(t, params):
					// Since Context.followWithAbstracts is used, only built-in types will be sent here
					var abstractType = t.get();
					switch abstractType.name {
						// Value types can always be converted
						case 'Int', 'Bool', 'Float': 
							if(alias == null) abstractType.name else alias;
						case _:
							var underlyingType = Context.followWithAbstracts(abstractType.type);
							var alias = typeAlias(abstractType.type);
							//trace(t + " -> " + underlyingType + ": " + alias);
							fieldTypeToName(underlyingType, field, alias);
					}
				case TType(t, params) if(params.length == 0):
					var t2 = t.get();
					var alias = t2.pack.toDotPath(t2.name);
					//var type = Context.followWithAbstracts(t2.type);
					fieldTypeToName(t2.type, field, alias);
				case TInst(t, params):
					var type = t.get();
					switch type.name {
						// String and Date can always be converted
						case 'String', 'Date': 
							if(alias == null) type.name else alias;
						// Arrays too
						case 'Array', 'IntMap', 'StringMap': 
							type.name + "<" + fieldTypeToName(params[0], field, null) + ">";
						case 'List':
							error("Lists aren't supported by DataClass, only Arrays.");
						case _:
							// But all other classes must implement DataClass
							var name = type.pack.toDotPath(type.name);
							if (!type.interfaces.exists(function(i) return i.t.get().name == "DataClass")) {
								error('Class $name does not implement DataClass.');
							}
							type.isInterface ? 'Interface<$name>' : 'DataClass<$name>';
					}
				case TDynamic(t) if(alias == "Dynamic"):
					'Dynamic';
				case _:
					error("Unsupported DataClass type: " + t.getName());
			}
		}
			
		return [for (field in dataClassFields) {
			var originalType = ComplexTypeTools.toType(field.type());
			var type = Context.followWithAbstracts(originalType);
			var alias = typeAlias(originalType);

			{
				#if (haxe_ver >= 4)
				quotes: null,
				#end
				field: field.name, 
				expr: macro $v{fieldTypeToName(type, field, alias)}
			}
		}];
	}
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
