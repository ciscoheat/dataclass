
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using haxe.macro.ExprTools;
using StringTools;

@:autoBuild(DataClassBuilder.build()) interface DataClass { }

class DataClassBuilder {
	#if macro	
	static function publicVarOrProp(f : Field) {
		if(f.access.has(AStatic) || !f.access.has(APublic)) return false;
		return switch(f.kind) {
			case FVar(_, _): true;
			// TODO: Make it work with setters too
			case FProp(_, set, _, _): set == "default" || set == "null";
			case _: false;
		}
	}

	static public function build() : Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass().get();

		// Fields aren't available on Context.getLocalClass().
		// need to supply them here. They're available on the superclass though.
		var publicFields = childAndParentFields(fields, cls).copy();
		var fieldMap = new Map<Field, {opt: Bool, def: Expr, val: Expr}>();
		var stringConvert = cls.meta.has("convert") ? cls.meta.extract("convert")[0] : null;

		for (f in publicFields) {
			// TODO: Allow fields with only a default value, no type
			var opt = switch f.kind {
				case FVar(TPath(p), _) if (p.name == "Null"): true;
				case FProp(_, _, TPath(p), _) if (p.name == "Null"): true;
				case _: false;
			}

			var def = switch f.kind {
				case FVar(TPath(p), e) if (e != null): 
					// Remove the Expr and return it
					f.kind = FVar(TPath(p), null);
					opt = true;
					e;
				case _: 
					macro null;
			}
			
			function createValidator(e : Expr) : Expr {
				var output : Expr;
				var name = f.name;
				var clsName = cls.name;				
				
				function replaceParam(e : Expr) return switch e.expr { 
					case EConst(CIdent("_")): macro this.$name;
					case _: e.map(replaceParam);
				}
				
				switch e.expr {
					case EConst(CRegexp(r, opt)):
						if (!r.startsWith('^')) r = '^' + r;
						if (!r.endsWith("$")) r += "$";						
						output = macro new EReg($v{r}, $v{opt}).match(this.$name);
					case _: 
						output = replaceParam(e);
				}
				
				e.expr = EConst(CString(e.toString()));
				return macro if(!$output) throw "Field " + $v{clsName} + "." + $v{name} + ' failed validation "' + $e + '" with value "' + this.$name + '"';
			}
			
			var validator = f.meta.find(function(m) return m.name == "validate");
			
			fieldMap.set(f, {
				opt: opt, 
				def: def, 
				val: validator == null ? null : createValidator(validator.params[0])
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
			
			var assignment = macro data.$name;
			
			if(stringConvert != null) switch f.kind {
				case FVar(TPath(p), _) | FProp(_, _, TPath(p), _):
					var typeName = switch p {
						case { name: "Null", pack: _, params: [TPType(TPath( { name: n, pack: _, params: _ } ))] } :
							n;
						case _:
							p.name;
					};
					
					assignment = switch typeName {
						case "Bool":
							macro !(~/^(?:false|no|0|)$/i.match(data.$name));
						case "Int":
							macro Std.parseInt(data.$name);
						case "Date":
							macro Date.fromString(data.$name);
						case "Float":
							var delimiter = stringConvert.params != null && stringConvert.params.length > 0
								? stringConvert.params[0].getValue() : '.';
							
							macro Std.parseFloat(new EReg("[^\\d.]", "g").replace(StringTools.replace(data.$name, $v { delimiter }, "."), ""));
						case _:
							assignment;
					}
				case _:
			}
			
			assignments.push(macro this.$name = data.$name != null ? $assignment : $def);
			
			if (!opt) assignments.push(
				macro if(this.$name == null) throw "Field " + $v{clsName} + "." + $v{name} + " was null."
			);
			
			if (val != null) assignments.push(val);
		};
		
		var constructor = fields.find(function(f) return f.name == "new");
		
		if (constructor == null) {
			if (cls.superClass != null)
				assignments.unshift(macro super(data));
				
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
						type: stringConvert != null ? (macro : Dynamic<String>) : TAnonymous(publicFields),
						opt: true,
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

	static function classFieldToField(c : ClassField) : Field {
		return {
			pos: c.pos,
			name: c.name,
			meta: c.meta.get(),
			kind: FVar(Context.toComplexType(c.type), null),
			doc: c.doc,
			access: [APublic]
		};
	}
	
	static function childAndParentFields(fields : Array<Field>, cls : ClassType) : Array<Field> {
		fields = fields.filter(publicVarOrProp);

		if(cls.superClass == null) return fields;

		var superClass = cls.superClass.t.get();
		return childAndParentFields(superClass.fields.get().map(classFieldToField), superClass).concat(fields);
	}
	#end
}