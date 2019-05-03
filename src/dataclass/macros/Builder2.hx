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
	isOption: Bool,
	isDate: Bool
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

			final isDate = switch f.kind {
				case FVar(t, e): switch t {
					case TPath(p) if(p.name == "Date"):	true;
					case _:	false;
				}
				case _: false;
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
				isOption: isOption,
				isDate: isDate
			}
		}

		final allFields = Context.getBuildFields();
		final dataclassFields = allFields.map(toDataClassField).filter(f -> f != null);
		final superclassFields = new DataClassType(cls).superclassFields();
		final constructorFields = superclassFields.map(toDataClassField).concat(dataclassFields);
		
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
			(macro var errors : dataclass.DataClassErrors = null, hasErrors = false),

			(macro function setError(field, value) {
				if(errors == null) errors = new dataclass.DataClassErrors();
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

		function ifIllegalValueSetError(f : DataClassField, validators : Array<Expr>) : Expr {
			function replaceValidators(vals : Array<Expr>) {
				// TODO: Check if validators exist
				//trace(vals.map(v -> v.toString()));

				function validatorExpr(e : Expr) {
					return switch e.expr {
						case EConst(CIdent("_")):
							// "v" var
							macro v;
						case _:
							e.map(validatorExpr);
					}
				}

				final newVals = vals.map(validatorExpr);
				final it = newVals.iterator();

				// Chain together the validators in an OR expression.
				function orOp(current : Expr) : Expr {
					switch current.expr {
						case EConst(CRegexp(_, _)):
							current = macro ${current}.match(Std.string(v));
						case _:
					}

					return if(!it.hasNext()) macro !($current);
					else macro !($current) || ${orOp(it.next())}
				}

				var ret = orOp(it.next());
				//trace(ret.toString());
				return ret;
			}

			// "v" var
			final extractValue = if(f.isOption)
				macro switch $p{['data', f.field.name]} {
					case None: null;
					case Some(v): v;
				}
			else
				macro $p{['data', f.field.name]};

			return macro {
				final v = $extractValue;
				if(${replaceValidators(validators)})
					setError($v{f.field.name}, haxe.ds.Option.Some(v));
			}
		}

		for(f in dataclassFields) {
			var name = f.field.name;
			//trace("*** " + name);
			switch f.nullability {
				// (1) No default value, cannot be null, no validator
				case None(validators) if(validators.length == 0):
					validateBoilerplate.push(macro 
						if($p{['data', name]} == null) 
							setError($v{name}, haxe.ds.Option.None)
					);

				// (3) No default value, cannot be null, has validator
				case None(validators):
					validateBoilerplate.push(macro 
						if($p{['data', name]} == null) 
							setError($v{name}, haxe.ds.Option.None)
						else
							${ifIllegalValueSetError(f, validators)}
					);

				/*(8)*/ 
				case Nullable(validators) if(validators.length == 0):

				// (2) No default value, can be null, has validator
				case Nullable(validators):
					validateBoilerplate.push(macro 
						${ifIllegalValueSetError(f, validators)}
					);

				/*(7)*/ 
				case DefaultValue(validators) if(validators.length == 0):

				// (4) Has default value, has validator
				case DefaultValue(validators):
					validateBoilerplate.push(macro 
						if($p{['data', name]} == null) 
							null
						else 
							${ifIllegalValueSetError(f, validators)}
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
				ret: macro : haxe.ds.Option<dataclass.DataClassErrors>
			}),
			name: 'validate',
			pos: cls.pos
		}

		///// - Generate constructor

		final allOptional = !dataclassFields.exists(f -> switch f.nullability {
			case None(_): true;
			case _: false;
		});

		final constructorFunction : Array<Expr> = [
			macro switch validate(data) { 
				case Some(errors): throw new dataclass.DataClassException(this, errors); 
				case None: 
			}
		];

		for(f in dataclassFields) {
			final dataField = macro $p{['data', f.field.name]};
			final thisField = macro $p{['this', f.field.name]};

			if(f.isDate && Context.defined('dataclass-date-auto-conversion')) constructorFunction.push(
				macro if($dataField != null && Std.is($dataField, String)) $thisField = dataclass.DateConverter.toDate(cast $dataField)
				else if($dataField != null && Std.is($dataField, Float) || Std.is($dataField, Int)) $thisField = Date.fromTime(cast $dataField)
				else if($dataField != null) $thisField = $dataField
			)
			else constructorFunction.push(
				// if(data.field != null) this.field = data.field			
				macro if($dataField != null) $thisField = $dataField
			);
		}

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

		///// - Generate copy method

		final copyFunction = {
			final copyFields = constructorFields.map(f -> {
				access: [],
				doc: f.field.doc,
				kind: switch f.field.kind {
					case FVar(t, _):
						FieldType.FVar(t, null);
					case _:
						Context.error("Variable fields and properties are not allowed in a DataClass. Use final instead.", f.field.pos);
				},
				meta: f.field.meta.concat([{
					name: ":optional",
					pos: f.field.pos
				}]),
				name: f.field.name,
				pos: f.field.pos
			});

			final copyFunction : Array<Expr> = [
				macro if(update == null) update = {}
			];

			for(f in copyFields) copyFunction.push(
				//if(!Reflect.hasField(update, "id")) update.id = this.id		
				macro if(!Reflect.hasField(update, $v{f.name})) $p{['update', f.name]} = $p{['dataClass', f.name]}
			);

			final clsType = {
				name: cls.name,
				pack: cls.pack
			}

			copyFunction.push(macro return new $clsType(cast update));

			{
				access: [APublic, AStatic],
				kind: FFun({
					args: [
						{
							name: 'dataClass',
							opt: false,
							type: TPath(clsType)
						},
						{
							name: 'update',
							opt: true,
							type: TAnonymous(copyFields)
						}
					],
					expr: macro $b{copyFunction},
					ret: TPath(clsType)
				}),
				name: 'copy',
				pos: cls.pos
			}
		}

		//////////////////////////////////////////////////////////////////

		for(f in allFields) {
			// Remove validation metadata for backwards compatibility
			if(f.meta.exists(m -> m.name == "validate"))
				Context.warning('@validate metadata is deprecated, use @:validate instead.', f.pos);

			f.meta = f.meta.filter(f -> f.name != "validate");
		}

		return allFields.concat([constructor, validateFunction, copyFunction]);
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
}
#end
