
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using haxe.macro.ExprTools;

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

	//static function publicVarName(f : Field) return f.name.charAt(0) != '_';

	static public function build() : Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass().get();

		// TODO: Inject at the start of constructor
		if(cls.constructor != null) return null;

		// Fields aren't available on Context.getLocalClass().
		// need to supply them here. They're available on the superclass though.
		var publicFields = childAndParentFields(fields, cls).copy();
		var fieldMap = new Map<Field, {opt: Bool, def: Expr, val: String}>();

		for (f in publicFields) {
			// TODO: Allow fields with only a default value, no type
			var opt = switch f.kind {
				case FVar(TPath(p), e) if (p.name == "Null"): true;
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
			
			var validator = f.meta.find(function(m) return m.name == "val");
			
			// TODO: String length validator (Integers)
			// TODO: String default values (DATE = \\d{4}...)
			var val = validator != null ? '^' + validator.params[0].getValue() + '$' : null;
			
			fieldMap.set(f, {opt: opt, def: def, val: val});

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
			
			assignments.push(macro this.$name = data.$name != null ? data.$name : $def);
			
			if (!opt) assignments.push(
				macro if(this.$name == null) throw "Field " + $v{clsName} + "." + $v{name} + " was null."
			);
			
			if (val != null) assignments.push(
				macro if (!new EReg($v{val}, "").match(this.$name))
					throw "Field " + $v{clsName} + "." + $v{name} + " failed validation " + $v{val}
			);
		};
		
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
					type: TAnonymous(publicFields),
					opt: true,
					name: 'data'
				}]
			}),
			doc: null,
			access: [APublic]
		});	

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