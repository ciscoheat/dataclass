package dataclass;

import haxe.macro.Expr;

#if macro
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.ds.Option;

using haxe.macro.ExprTools;
using Lambda;
using StringTools;

@:publicFields @:structInit private class DataClassInfo {    
    // The identifier used for the structure
    final identifier : Expr;
    
    // All fields in the current structure
    final fields : Array<ObjectField>;

    // Type as determined by the macro Context.
    // If instance, 
    final currentType : Option<Type>;
}
#end

enum DataMapField
{
    Same;
    SameInt;
    SameFloat;
    SameString;
    SameFloatToInt;
}

class DataMap
{
    #if macro

    // Map an expression for a field to the real expression
    static function mapField(from : Expr, fromType : Null<Type>, field : ObjectField) : Expr {
        function identifier(name) return {expr: EField(from, name), pos: field.expr.pos};

        return switch field.expr.expr {
            // Lambda functions on an Array field
            case EFunction(FArrow, func): 
                if(func.expr == null) return Context.error("No object declaration in function", func.expr.pos);

                final forVar = macro $i{func.args[0].name};
                final functionField = switch func.args.length {
                    case 1: field.field;
                    case 2: func.args[1].name;
                    case _: Context.error("Unsupported arguments in lambda function", func.expr.pos);
                }
                final forIterate = identifier(functionField);
                
                switch func.expr.expr {
                    case EMeta(_, {expr: EReturn(e), pos: _}): 
                        final structureFields = objectFields(e);
                        final structureType = switch e.expr {
                            case ENew(typePath, _): ComplexTypeTools.toType(TPath(typePath));
                            case _ if(fromType != null): returnTypeIfArray(returnTypeForField(fromType, field.field));
                            case _: null;
                        }

                        //final structure = createNew(fromType, mapStructure(structureFields, forVar, structureType));
                        final structure = mapStructure(structureFields, forVar, structureType);
        
                        macro [for($forVar in $forIterate) $structure];
        
                    case _: 
                        Context.error("Lambda function can only contain an anonymous structure or an instantiation of a Dataclass.", func.expr.pos);
                }

            case _:
                mapExpr(identifier(field.field), field.expr);
        }
    }

    static function mapExpr(ident : Expr, e : Expr) return switch e.expr {

        ///// Map Same-identifiers to Std functions /////

        case EConst(CIdent("Same")):                 
            ident;

        case EConst(CIdent("SameString")):
            macro Std.string($ident);

        case EConst(CIdent("SameInt")):
            macro Std.parseInt($ident);

        case EConst(CIdent("SameFloat")):
            macro Std.parseFloat($ident);

        case EConst(CIdent("SameFloatToInt")):
            macro Std.int($ident);

        case _: 
            e.map(mapExpr.bind(ident));
    }

    static function objectFields(e : Expr) return switch e.expr {
        case EObjectDecl(fields) | ENew(_, [{expr: EObjectDecl(fields), pos: _}]):
            fields;
        case _: 
            Context.error("Required: Anonymous object declaration or object instantiation.", e.pos);
    }

    static function mapStructure(fields : Array<ObjectField>, from : Expr, fromType : Null<Type>) : Expr {
        final newObj = EObjectDecl(fields.map(f -> {
            field: f.field,
            expr: mapField(from, fromType, f),
            quotes: f.quotes
        }));

        return createNew(fromType, {expr: newObj, pos: Context.currentPos()});
    }

    /**
     * The "Same" values will mess up autocompletion, so typecheck them to Any.
     * Will only happen in display mode.
     */
     static function mapSameForDisplay(e : Expr) : Expr {
        return switch e.expr {
            case EConst(CIdent(s)): switch s {
                case "Same" | "SameString" | "SameInt" | "SameFloat" | "SameFloatToInt":
                    {expr: ECheckType(e, macro : Any), pos: e.pos};
                case _: 
                    e.map(mapSameForDisplay);
            }

            case _: e.map(mapSameForDisplay);
        }
    }

    static function returnTypeIfArray(type : Type) : Null<Type> {
        return switch type {
            case TLazy(f): returnTypeIfArray(f());
            case TInst(t, params) if(t.get().name == "Array"): params[0];
            case _: null;
        }
    }

    static function returnTypeForField(type : Type, fieldName : String) : Null<Type> {   
        return switch type {
            case TLazy(f): 
                returnTypeForField(f(), fieldName);

            case TInst(t, _): 
                final field = t.get().fields.get().find(f -> f.name == fieldName);
                if(field == null) Context.error('Field not found on $type: ' + fieldName, Context.currentPos());
                else field.type;

            case TAnonymous(a):
                final field = a.get().fields.find(f -> f.name == fieldName);
                if(field == null) Context.error('Field not found on $type: ' + fieldName, Context.currentPos());
                else field.type;

            case _:
                null;
        }
    }

    static function createNew(type : Null<Type>, fromStructure : Expr) return switch type {
        case TInst(t, _) if(!t.get().meta.has(":structInit")):
            switch Context.toComplexType(type) {
                case TPath(p): macro new $p($fromStructure);
                case _: fromStructure;
            }
        case _: fromStructure;
    }
   
    #end

    public static macro function dataMap(from : Expr, structure : Expr) {
        if(Context.defined("display")) return mapSameForDisplay(structure);

        final expectedType = switch structure.expr {
            case ENew(t, _): ComplexTypeTools.toType(TPath(t));
            case _: Context.getExpectedType();
        }

        return mapStructure(objectFields(structure), from, expectedType);
    }
}
