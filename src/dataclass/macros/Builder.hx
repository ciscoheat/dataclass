package dataclass.macros;
import haxe.DynamicAccess;
import haxe.macro.ComplexTypeTools;
import haxe.macro.MacroStringTools;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.MacroStringTools;
using Lambda;
using StringTools;

private typedef FieldDataProperties = {
	optional: Bool, 
	defaultValue: Expr, 
	validator: Expr
}

private typedef DataClassField = {
	> Field,
	var validation(default, null) : Array<Expr>;
}

@:forward(name, access, doc, meta, pos, validation)
private abstract DataField(DataClassField) to Field
{
	inline function new(f : DataClassField) this = f;
	
	@:from static public function fromField(f : Field) {
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
	
	public function isDataClassField() return
		isVarOrProp() &&
		!this.access.has(AStatic) &&
		!this.meta.exists(function(m) return m.name == 'exclude') &&
		(this.access.has(APublic) || this.meta.exists(function(m) return m.name == 'include'));

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

	function canBeNull() return switch type() {
		case TPath(p): p.name == "Null" || (p.name == "StdTypes" && p.sub == "Null");
		case _: false;
	}
	
	public function defaultValue() : Null<Expr> return switch this.kind {
		case FVar(_, e), FProp(_, _, _, e): e;
		case _: null;
	}	
}

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
		
		return classFields.map(function(f) return {
			pos: f.pos,
			name: f.name,
			meta: f.meta.get(),
			kind: switch f.kind {
				case FVar(read, write):
					function toPropType(access : VarAccess, read : Bool) {
						return switch access {
							case AccNormal: 'default';
							case AccNo: 'null';
							case AccNever: 'never';
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
			access: f.isPublic ? [APublic] : []
		}).map(function(f) return DataField.fromField(f)).array();
	}	
	
	public function isImmutable() return this.meta.has("immutable");
	
	public function shouldAddValidator() return !this.meta.has("noValidator");
	
	// TODO: Throw custom class
	/*
	public function throwCustom() return Context.defined("dataclass-throw")
		? Context.definedValue("dataclass-throw").split(".") : null;
	*/
	
	public function implementsInterface(interfaceName : String) {
		return this.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == interfaceName;
		});
	}
}

class Builder
{
	// String is not needed since it won't be converted
	//static var supportedConversions(default, null) = ["Bool" => true, "Date" => true, "Int" => true, "Float" => true];

	var CLASS(default, null) : DataClassType;
	var OTHERFIELDS(default, null) : Array<Field>;
	var DATACLASSFIELDS(default, null) : Array<DataField>;
		
	static public function build() : Array<Field> {
		var cls = Context.getLocalClass().get();
		if (cls.isInterface) return null;
		
		return new Builder().createDataClassFields();
	}
	
	function new() {		
		var allFields = Context.getBuildFields();
		
		CLASS = new DataClassType(Context.getLocalClass().get());		
		OTHERFIELDS = allFields.filter(function(f) return !DataField.fromField(f).isDataClassField());
		DATACLASSFIELDS = allFields
			.map(function(f) return DataField.fromField(f))
			.filter(function(f) return f.isDataClassField());
			
		//trace('Other: ' + OTHERFIELDS.map(function(f) return f.name));
		//trace('DataClassFields: ' + DATACLASSFIELDS.map(function(f) return f.name));
		
		if (CLASS.shouldAddValidator()) {
			var validateField = OTHERFIELDS.find(function(f) return f.name == "validate");
			if(validateField != null)
				Context.error("DataClass without @noValidator metadata cannot have a method called 'validate'", validateField.pos);
		}		
	}

	function throwFailedValidation(message : String, arg : Expr) {
		return CLASS.implementsInterface("HaxeContracts")
			? macro throw new haxecontracts.ContractException($v{message}, this, $arg)
			: macro throw $v{message};
	}
			
	function dataClassFieldsIncludingSuperFields()
		return CLASS.superclassFields().concat(DATACLASSFIELDS);

	function areAllDataClassFieldsOptional() 
		return !dataClassFieldsIncludingSuperFields().exists(function(f) return !f.isOptional());
			
	// Entry point 
	function createDataClassFields() : Array<Field> {
		//trace("======= " + CLASS.name);
		
		var newSetters = [];

		function createNewSetter(field : DataField) {
			var fieldName = field.name;
			var argName = 'v';
			var errorMsg = "Validation failed for " + CLASS.name + "." + field.name;
			var identifier = macro $i{argName};
			var validationExpr = createValidationTestExpr(field, identifier, throwFailedValidation(errorMsg, identifier));
			
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
			
			// Setters are used for validation, so create a setter if access is default
			if (setAccess == 'default') {
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

				var errorMsg = "Validation failed for " + CLASS.name + "." + field.name;
				var identifier = macro $i{param.name};
				var validationTestExpr = createValidationTestExpr(field, identifier, throwFailedValidation(errorMsg, identifier));
				
				switch func.expr.expr {
					case EBlock(exprs): exprs.unshift(validationTestExpr);
					case _: func.expr = {expr: EBlock([validationTestExpr, func.expr]), pos: func.expr.pos};
				}
			}
			
			return {
				access: field.access,
				doc: field.doc,
				kind: FProp(field.getAccess(), setAccess, field.type(), field.defaultValue()),
				meta: field.meta.filter(function(m) return m.name != 'validate'),
				name: field.name,
				pos: field.pos
			}
		});
		
		// Create metadata for ORM
		function ormFieldType(t : Type, field : DataField) : String {
			function error(msg = "Unsupported DataClass type, mark with @exclude if it's required.") {
				Context.error(msg, field.pos);
				return null;
			}
			
			return switch t {
				case TEnum(enumType, _):
					var e = enumType.get();
					for (c in e.constructs) if (c.params.length > 0) 
						error("Only Enums without constructors can be a DataClass field.");
					"Enum<" + e.pack.toDotPath(e.name) + ">";
				case TAbstract(t, params):
					var type = t.get();
					switch type.name {
						case 'Int', 'Bool', 'Float': type.name;
						case _: error();
					}
				case TInst(t, params):
					var type = t.get();
					switch type.name {
						case 'String', 'Date': type.name;
						case 'Array': "Array<" + ormFieldType(params[0], field) + ">";
						case _:
							var name = type.pack.toDotPath(type.name);
							if (!type.interfaces.exists(function(i) return i.t.get().name == "DataClass"))
								error('Class $name does not implement DataClass.');
							name;
					}
				case _:
					error();
			}
		}
			
		var ormMetadata = [for (field in newDataClassFields) switch field.kind {
			case FProp(_, _, t, _):
				var type = Context.followWithAbstracts(ComplexTypeTools.toType(t));
				{
					field: field.name, 
					expr: macro $v{ormFieldType(type, field)}
				}
			case _: Context.error("Invalid DataClass field", field.pos);
		}];
		
		//trace('===== ' + CLASS.name);
		//trace(ormMetadata.map(function(f) return f.field + ": " + f.expr.toString()));

		CLASS.meta.add("dataClassRtti", [{expr: EObjectDecl(ormMetadata), pos: CLASS.pos}], CLASS.pos);
		
		// As a last step, need to remove @validate from superclass fields, otherwise their Expr won't compile.
		for (superClassField in CLASS.superClasses().flatMap(function(f) return f.fields.get())) {
			superClassField.meta.remove('validate');
		}
		
		var normalFieldsWithoutConstructor = OTHERFIELDS.filter(function(f) return f.name != 'new');
				
		//for (f in newDataClassFields) trace(f.name + " -> " + f.kind);
		
		return normalFieldsWithoutConstructor
			.concat([createValidator(), createConstructor()])
			.concat(newDataClassFields)
			.concat(newSetters)
			.filter(function(f) return f != null);
	}
	
	function createValidationTestExpr(field : DataField, testField : Expr, failExpr : Expr) : Expr {
		var testExpr = Validator.createValidatorTestExpr(field.type(), testField, field.isOptional(), field.validation);
		
		return switch testExpr {
			case None: macro null;
			case Some(testExpr): macro if ($testExpr) $failExpr;
		}
	}
	
	function createValidator() : Null<Field> {
		if (!CLASS.shouldAddValidator()) 
			return null;
		
		var argName = 'data';
		var validationTests = dataClassFieldsIncludingSuperFields().map(function(f) {
			var testFieldAccessor = macro $p{[argName, f.name]};
			var fieldExists = macro Reflect.hasField($i{argName}, $v{f.name});
			var addToOutput = macro output.push($v{f.name});
			var isOptional = macro $v{f.isOptional()};
			
			var testExpr = switch Validator.createValidatorTestExpr(f.type(), testFieldAccessor, f.isOptional(), f.validation) {
				case None: macro false;
				case Some(e): e;
			}
			
			return macro {
				if (!$isOptional && !$fieldExists) $addToOutput
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
					type: assignmentAnonymousType(true),
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
	
	function createConstructor() {
		// Returns all field assignments based on the first constructor parameter.
		// "this.name = data.name"
		function constructorAssignments(fieldName : String) : Expr {
			var assignments = dataClassFieldsIncludingSuperFields().filter(function(f) {
				var access = f.setAccess(CLASS.isImmutable());
				return access != 'never';
			})
			.map(function(f : DataField) {
				var assignment = macro $p{['this', f.name]} = $p{[fieldName, f.name]};
				
				return f.isOptional()
					? (macro if(Reflect.hasField($i{fieldName}, $v{f.name})) $assignment)
					: assignment;
			});
			
			//trace(assignments.map(function(a) return a.toString()).join(";\n"));
			
			var block = areAllDataClassFieldsOptional()
				? (macro if ($i{fieldName} != null) $b{assignments}) 
				: macro $b{assignments};
			
				
			return block;
		}
		
		var existing : Field = OTHERFIELDS.find(function(f) return f.name == 'new');
		
		var arguments : Array<FunctionArg> = if (existing != null) {
			switch existing.kind {
				case FFun(f):
					// Testing for a correct constructor definition
					if (f.args.length == 0) {
						Context.error("The DataClass constructor must have at least one parameter.", f.expr.pos);
					}					
					else if (f.args[0].type != null) {
						Context.warning("The first parameter in a DataClass constructor cannot have a type.", f.expr.pos);
					} else if (areAllDataClassFieldsOptional() && (f.args[0].opt == null || !f.args[0].opt)) {
						Context.error("All DataClass fields are optional, so the first constructor parameter must also be optional.", f.expr.pos);
					} else if (f.args[0].value != null) {
						Context.error("The first parameter in a DataClass constructor cannot have a default value.", f.expr.pos);
					}
					for (arg in f.args.slice(1)) {
						if ((arg.opt == null || arg.opt == false) && arg.value == null) {
							Context.error("All subsequent constructor parameters in a DataClass must be optional", f.expr.pos);
						}
					}
					
					// Set type for first argument, and return the args structure
					// TODO: Code completion doesn't work for the constructor parameter
					f.args[0].type = assignmentAnonymousType();
					
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
			type: assignmentAnonymousType(),
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
	
	// allOptional is used in the static "validate" method, so any object can be used.
	function assignmentAnonymousType(allOptional = false) : ComplexType {
		var fields = dataClassFieldsIncludingSuperFields().map(function(f) return {
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

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

class Builder2
{
	// String is not needed since it won't be converted
	static var supportedConversions(default, null) = ["Bool" => true, "Date" => true, "Int" => true, "Float" => true];
	
	static public function build() : Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass().get();
		
		if (cls.meta.has("immutable")) 
			Context.error("@immutable is deprecated, use '-lib immutable' and 'implements Immutable' instead.", cls.pos);
		
		// Fields aren't available on Context.getLocalClass().
		// need to supply them here. They're available on the superclass though.
		var dataClassFields = includedFields(fields, cls);
		var fieldMap = new Map<Field, FieldDataProperties>();
		
		// Test if class implements HaxeContracts, then throw ContractException instead.
		var haxeContracts = cls.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == "HaxeContracts";
		});

		// Test if class implements Immutable, then don't create any setters.
		var immutable = cls.interfaces.map(function(i) return i.t.get()).exists(function(ct) {
			return ct.name == "Immutable";
		});

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
			
			var optional = switch f.kind {
				case FVar(TPath(p), _) | FProp(_, _, TPath(p), _): 
					// StdTypes.Null is created when Context.toComplexType is used.
					p.name == "Null" || (p.name == "StdTypes" && p.sub == "Null");
				
				case _: 
					false;
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
		var dataValidationExpressions = [];
		var anonymousValidationFields : Array<Field> = [];
		var allOptional = ![for (f in fieldMap) f].exists(function(f) return f.optional == false);
		var convertFrom = [];
		var convertTo = [];
		var fullConversion = [];
		
		for (f in dataClassFields) {
			var data = fieldMap.get(f);
			var defaultValue = data.defaultValue;
			var optional = data.optional;
			var validator = data.validator;
			var name = f.name;
			var clsName = cls.name;
			
			var fieldType = switch f.kind {
				case FVar(t, _), FProp(_, _, t, _): t;
				case FFun(f): f.ret;
			}
			
			var assignment = optional
				? macro data.$name != null ? data.$name : $defaultValue
				: macro data.$name;
				
			// Create a new Expr to set the correct pos
			assignment = { expr: assignment.expr, pos: f.pos };
			
			// If the type can be converted using the DynamicObjectConverter, mark it with metadata
			switch f.kind {
				case FVar(TPath(p), _) | FProp(_, _, TPath(p), _):
					#if (haxe_ver >= 3.3)
					var type = Context.followWithAbstracts(ComplexTypeTools.toType(TPath(p)));
					#else
					var type = Context.follow(ComplexTypeTools.toType(TPath(p)));
					#end
					var typeName = switch type {
						case TInst(t, _) if (t.get() != null): 
							MacroStringTools.toDotPath(t.get().pack, t.get().name);
						case TAbstract(t, _) if (t.get() != null): 
							MacroStringTools.toDotPath(t.get().pack, t.get().name);
						case _: 
							"";
					}
					
					if (Converter.DynamicObjectConverter.supportedTypes.exists(typeName)) {
						// convertFrom is for incoming fields
						//trace(cls.name + ":" + f.name + " -> " + typeName);
						convertFrom.push({field: f.name, expr: macro $v{typeName}});

						// convertTo excludes non-public fields in conversions
						if (f.access.has(APublic)) 
							convertTo.push({field: f.name, expr: macro $v{typeName}});
					}
				case _:
			}
			
			// Add full conversion metadata
			function isDataClass(t : Type) : String return switch t {
				case TInst(t, _) if (t.get().interfaces.exists(function(i) return i.t.get().name == "DataClass")):
					MacroStringTools.toDotPath(t.get().pack, t.get().name);
				case _: 
					null;
			};
			
			switch f.kind {
				case FVar(TPath(p), _) | FProp(_, _, TPath(p), _):
					if (p.name == "Null") switch(p.params[0]) {
						case TPType(TPath(p2)): p = p2;
						case _:
					}
					
					var isArray = p.name == "Array" && p.pack.length == 0;
					var arrayType = if(isArray) switch p.params[0] {
						case TPType(t): ComplexTypeTools.toType(t);
						case _: null;
					} else null;
					
					var type = isArray ? arrayType : ComplexTypeTools.toType(TPath(p));
					var name = isDataClass(type);
					
					var data = if (name == null) {
						// If it's a basic type, make it convertable with * syntax:
						p.pack.length == 0 && supportedConversions.exists(p.name) ? '*${p.name}' : "";
					}
					else { 
						// It's a DataClass, if it's an array use [ syntax.
						isArray ? '[$name' : name;
					}
					
					fullConversion.push({ field: f.name, expr: macro $v{data} });
				case _:
			}			
			
			function setterAssignmentExpressions(param : String, existingSetter : Null<Expr>) : Array<Expr> {
				function fieldAssignmentTests(param : String) : Array<Expr> {				
					var assignments = [];

					if (!optional && Validator.nullTestAllowed(fieldType)) {
						var throwStatement = throwError(macro "Field " + $v{clsName} + "." + $v{name} + " was null.");
						assignments.push(macro if ($i{param} == null) $throwStatement);
					}
					
					if (validator != null) {
						var errorString = macro "Field " + $v{clsName} + "." + $v{name} + ' failed validation "' + $validator + '" with value "' + $i{name} + '"';
						//assignments.push(Validator.createValidator(fieldType, macro $i{param}, optional, validator, throwError(errorString), false));
					}
					
					return assignments;
				}
				
				if (existingSetter == null) existingSetter = {expr: EBlock([]), pos: f.pos};
				switch existingSetter.expr {
					case EBlock(exprs):
						var assignments = fieldAssignmentTests(param);						
						if (exprs.length == 0) assignments.push(macro return this.$name = $i{param});
						
						return assignments.concat(exprs);
						
					case _: 
						return setterAssignmentExpressions(param, {expr: EBlock([existingSetter]), pos: existingSetter.pos});
				}				
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
				
				// Assumptions for these expressions: data is Dynamic<Dynamic>, failed an Array<String>
				// will be used to create a static "validate" field on each DataClass implemented type.
				/*
				dataValidationExpressions.push(Validator.createValidator(
					fieldType, macro $p{['data', name]}, optional, validator, 
					macro failed.push($v{name}), !optional // Test field existence only for non-optional fields
				));
				*/
			}

			switch f.kind {
				case FVar(type, e):
					if(!immutable) {
						f.kind = FProp("default", "set", type, null);
						// Add a setter function to the class.
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
					else {
						f.kind = FProp("default", "null", type, null);
					}
						
					createAnonymousValidationField(type);

				// If a property setter already exists, inject validation into the beginning of it.
				case FProp(get, set, type, e) if (set == "set"):
					var accessorField = fields.find(function(f2) return f2.name == "set_" + f.name);
					switch accessorField.kind {
						case FFun(f2):
							f2.expr.expr = EBlock(setterAssignmentExpressions(f2.args[0].name, f2.expr));
						case _:
							Context.error("Invalid setter accessor", accessorField.pos);
					}
					createAnonymousValidationField(type);
					
				case FProp(_, set, type, _):
					createAnonymousValidationField(type);
					
				case FFun(_):
			}
			
			// Add to assignment in constructor
			assignments.push(macro @:pos(f.pos) this.$name = $assignment);
			
			if(validator != null) {
				// Set the validator expr to a const so it will pass compilation
				validator.expr = EConst(CString(validator.toString()));
			}
		}

		cls.meta.add("dataClassFields", [for(f in dataClassFields) if(f.access.has(APublic)) macro $v{f.name}], cls.pos);

		// Add convertFrom/To metadata to class
		cls.meta.add(
			"convertFrom", 
			[{expr: EObjectDecl(convertFrom), pos: cls.pos}],
			cls.pos
		);

		cls.meta.add(
			"convertTo", 
			[{expr: EObjectDecl(convertTo), pos: cls.pos}],
			cls.pos
		);

		// Add fullConversion data
		cls.meta.add(
			"fullConv", 
			[{expr: EObjectDecl(fullConversion), pos: cls.pos}],
			cls.pos
		);

		
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
		
		// Create a static validation method
		
		dataValidationExpressions.unshift(macro var failed = []);
		// All the validation expressions are now located here
		dataValidationExpressions.push(macro return failed);
		
		//trace(dataValidationExpressions.map(function(e) return e.toString() + "\n"));
		
		var validate = if(cls.isInterface) [] else [{
			pos: Context.currentPos(),
			name: 'validate',
			meta: null,
			kind: FFun({
				ret: macro : Array<String>,
				params: null,
				expr: {expr: EBlock(dataValidationExpressions), pos: Context.currentPos()},
				args: [{
					value: null,
					type: macro : Dynamic,
					opt: false,
					name: 'data'
				}]
			}),
			doc: null,
			access: [APublic, AStatic]
		}];

		return fields.concat(validationFields).concat(validate);
	}
	
	////////////////////////////////////////////////////////////////////////////////
	
	static function ignored(f : Field) {
		return !f.meta.exists(function(m) return m.name == "ignore" || m.name == "exclude");
	}

	static function publicVarOrPropOrIncluded(f : Field) {
		if (f.meta.exists(function(m) return m.name == "include")) return true;
		if (f.access.has(AStatic) || !f.access.has(APublic)) return false;
		if (f.kind == null) return false;
		
		return switch(f.kind) {
			case FVar(_, _): true;
			case FProp(_, set, _, _): 
				// Need to test accessor method if it starts with set. It can be both "set" and "set_method".
				set == "default" || set == "null" || set.startsWith("set");
			case _: false;
		}
	}

	static function includedFields(fields : Array<Field>, cls : ClassType) : Array<Field> {
		var superClass = cls.superClass == null ? null : cls.superClass.t.get();
			
		var allFields = superClass == null 
			? fields
			: fields.concat(superclassFields(superClass));
			
		// Need to remove the validate meta from the superClass, unless it also implements Dataclass.
		if (superClass != null && !superClass.interfaces.exists(function(i) return i.t.get().name == 'DataClass')) {
			for (field in superClass.fields.get()) {
				field.meta.remove("validate");
			}			
		}
			
		return allFields.filter(ignored).filter(publicVarOrPropOrIncluded);
	}
	
	static function superclassFields(cls : ClassType) : Array<Field> {
		return includedFields(cls.fields.get().map(function(f) return {
			pos: f.pos,
			name: f.name,
			meta: f.meta.get(),
			kind: switch f.kind {
				case FVar(read, write):
					function toPropType(access : VarAccess, read : Bool) {
						return switch access {
							case AccNormal: 'default';
							case AccNo: 'null';
							case AccNever: 'never';
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
			access: f.isPublic ? [APublic] : []
		}), cls);
	}
}
#end