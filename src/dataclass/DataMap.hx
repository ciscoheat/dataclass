package dataclass;

import haxe.macro.Expr;

#if macro
import haxe.ds.Option;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using Lambda;
using StringTools;

@:publicFields @:structInit private class DataClassInfo {    
    // The identifier used for the field. "person" in person.name
    final identifier : Expr;
    
    // All fields in the current object
    final fields : Array<ObjectField>;
    
    final currentType : Type;
}
#end

class DataMap
{
    #if macro

    ///// Helpers ///////////////////////////////////////////////

    static function toAnonField(e : Expr) return switch e.expr {
        case EObjectDecl(fields): fields;
        case _: Context.error("Required: Anonymous object declaration.", e.pos);
    }    

    static function createNew(type : Type, structure : Expr) {
        return switch type {
            case TInst(t, _): 
                if(t.get().meta.has(":structInit")) structure
                else switch Context.toComplexType(type) {
                    case TPath(p): macro new $p($structure);
                    case _: Context.error("Invalid type: " + type, Context.currentPos());
                }
            case _: structure;
        }
    }
   
    static function mapStructure(info : DataClassInfo) : Expr {
        final newObj = EObjectDecl(info.fields.map(f -> {
            field: f.field,
            expr: mapField(info, f.field, f.expr),
            quotes: f.quotes
        }));

        return {expr: newObj, pos: Context.currentPos()};
    }

    static function returnType(type : Type, fieldName : String) : Type {
        return switch type {
            case TLazy(f): returnType(f(), fieldName);
            case TInst(t, params) if(t.get().name == "Array"):
                //trace(params[0]);
                params[0];
            case TInst(t, _):
                //trace("----- " + type);
                final fields = t.get().fields.get();
                //trace(fields.map(f -> f.name));
                returnType(fields.find(f -> f.name == fieldName).type, fieldName);
            case e: 
                Context.error("Unsupported type for dataMap: " + e, Context.currentPos());
        }
    }

    // Map an expression for a field to the real expression
    static function mapField(info : DataClassInfo, fieldName : String, e : Expr) : Expr {
        function identifier(name) return {expr: EField(info.identifier, name), pos: e.pos};

        return switch e.expr {
            case EFunction(FArrow, f): 
                //trace('========== Function: $fieldName');
                if(f.expr == null) return Context.error("No object declaration in function", e.pos);
                
                final functionField = switch f.args.length {
                    case 1: fieldName;
                    case 2: f.args[1].name;
                    case _: Context.error("Unsupported arguments in lambda function", e.pos);
                }

                final forVar = f.args[0].name;
                final forIterate = identifier(functionField);

                final structure = createNew(returnType(info.currentType, fieldName), mapStructure({
                    identifier: macro $i{forVar},
                    fields: switch f.expr.expr {
                        case EMeta(_, {expr: EReturn({expr: EObjectDecl(fields), pos: _}), pos: _}): fields;
                        case _: Context.error("Lambda function can only contain an anonymous structure.", f.expr.pos);
                    },
                    currentType: returnType(info.currentType, fieldName)
                }));

                macro [for($i{forVar} in $forIterate) $structure];

            case EConst(CIdent("Same")): 
                {expr: EField(info.identifier, fieldName), pos: e.pos};

            case _: 
                e.map(mapField.bind(info, fieldName));
        }
    }

    #end

    public static macro function dataMap(from : Expr, toStructure : Expr, ?returns : Expr) {
        final expectedType = if(returns.expr.equals(EConst(CIdent("null"))))
            Context.getExpectedType();
        else
            Context.getType(returns.toString());

        if(expectedType == null) Context.error("No return type found, please specify it.", Context.currentPos());

        final structure = mapStructure({
            identifier: from,
            fields: toAnonField(toStructure),
            currentType: expectedType
        });

        //trace(structure.toString().replace("[", "\n\t[").replace("{", "\n\t{"));

        return createNew(expectedType, structure);
    }
}
