package dataclass;

import haxe.macro.ComplexTypeTools;
import haxe.macro.TypeTools;
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
            case TInst(t, params) if(t.get().name == "Array"): params[0];
            case TInst(t, _):
                //trace("----- " + type);
                final fields = t.get().fields.get();
                returnType(fields.find(f -> f.name == fieldName).type, fieldName);
            case e: 
                Context.error("Unsupported type for dataMap: " + e, Context.currentPos());
        }
    }

    // Map an expression for a field to the real expression
    static function mapField(info : DataClassInfo, fieldName : String, e : Expr) : Expr {
        function identifier(name) return {expr: EField(info.identifier, name), pos: e.pos};

        return switch e.expr {
            case EArrayDecl([{expr: EFor({expr: EBinop(op, e1, e2), pos: _}, forExpr), pos: _}]): 
                switch forExpr.expr {
                    case ENew(typePath, [structure]): switch structure.expr {
                        case EObjectDecl(fields):
                            structure.expr = mapStructure({
                                identifier: e1,
                                fields: fields,
                                currentType: ComplexTypeTools.toType(TPath(typePath))
                            }).expr;
                            e;
                        case _:
                            trace(e.expr);
                            Context.error("Unsupported for expression", e.pos);    
                    }                        
                    case _:
                        Context.error("Unsupported for expression 2", e.pos);
                }

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
                final returnType = switch f.expr.expr {
                    case EMeta(_, {expr: EReturn({expr: ENew(typePath, _), pos: _}), pos: _}): 
                        ComplexTypeTools.toType(TPath(typePath));
                    case _: 
                        returnType(info.currentType, fieldName);
                }                

                final structure = createNew(returnType, mapStructure({
                    identifier: macro $i{forVar},
                    fields: switch f.expr.expr {
                        case EMeta(_, {expr: EReturn({expr: EObjectDecl(fields), pos: _}), pos: _}): fields;
                        case EMeta(_, {expr: EReturn({expr: ENew(typePath, [{expr: EObjectDecl(fields), pos: _}]), pos: _}), pos: _}): fields;
                        case _: Context.error("Lambda function can only contain an anonymous structure or an instantiation of a Dataclass.", f.expr.pos);
                    },
                    currentType: returnType
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

        function toAnonField(e : Expr) return switch e.expr {
            case EObjectDecl(fields): fields;
            case _: Context.error("Required: Anonymous object declaration.", e.pos);
        }    
    
        final structure = mapStructure({
            identifier: from,
            fields: toAnonField(toStructure),
            currentType: expectedType
        });

        //trace(structure.toString().replace("[", "\n\t[").replace("{", "\n\t{"));

        return createNew(expectedType, structure);
    }
}
