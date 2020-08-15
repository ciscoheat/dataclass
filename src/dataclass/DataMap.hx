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
    public static macro function dataMap(from : Expr, to : Expr) {
        if(Context.defined("display")) return mapSameForDisplay(to);

        final expectedType = switch to.expr {
            case ENew(t, [{expr: EObjectDecl(_), pos: _}]): ComplexTypeTools.toType(TPath(t));
            case EObjectDecl(_): Context.getExpectedType();
            case _: null;
        }

        return if(expectedType != null)
            mapStructure(objectFields(to), from, expectedType)
        else
            mapExpr(from, null, to);
    }

    ///////////////////////////////////////////////////////////////////////////

    #if macro

    // Map an expression for a field to the real expression
    static function mapField(from : Expr, fromType : Null<Type>, field : ObjectField) : Expr {        
        return switch field.expr.expr {  

            // A lambda function on an Array field is transformed to an array comprehension for loop
            case EFunction(FArrow, func): 
                if(func.expr == null) return Context.error("No object declaration in function.", func.expr.pos);

                final forVar = macro $i{func.args[0].name};
                final functionField = switch func.args.length {
                    case 1: field.field;
                    case 2: func.args[1].name;
                    case _: Context.error("Unsupported number of arguments in lambda function.", func.expr.pos);
                }
                final forIterate = {expr: EField(from, functionField), pos: field.expr.pos};
                
                // Figure out if an object should be instantiated.
                switch func.expr.expr {
                    case EMeta(_, {expr: EReturn(e), pos: _}): 
                        final structureType = switch e.expr {
                            case ENew(typePath, _): 
                                ComplexTypeTools.toType(TPath(typePath));
                            case EObjectDecl(_) if(fromType != null): 
                                extractTypeFromArray(returnTypeForField(fromType, field.field));
                            case _: null;
                        }
                        
                        final structure = if(structureType != null)
                            mapStructure(objectFields(e), forVar, structureType);
                        else
                            mapExpr(forVar, field.field, e);
        
                        macro [for($forVar in $forIterate) $structure];
        
                    case _: 
                        Context.error("Must be a lambda function.", func.expr.pos);
                }

            case _:
                mapExpr(from, field.field, field.expr);
        }
    }

    static function mapExpr(ident : Expr, currentField : Null<String>, e : Expr) {
        function identifier() {
            return {expr: EField(ident, currentField), pos: ident.pos};
        }

        return switch e.expr {
            case EFor({expr: EBinop(OpIn, e1, e2), pos: _}, forExpr):
                macro for($e1 in $e2) ${mapExpr(e1, currentField, forExpr)};

            case EObjectDecl(fields):
                mapStructure(fields, ident, null);

            case ENew(typePath, [{expr: EObjectDecl(fields), pos: _}]):
                mapStructure(fields, ident, ComplexTypeTools.toType(TPath(typePath)));
        
            case EConst(CIdent("Same")):
                identifier();

            case EConst(CIdent("SameString")):
                macro Std.string(${identifier()});

            case EConst(CIdent("SameInt")):
                macro Std.parseInt(${identifier()});

            case EConst(CIdent("SameFloat")):
                macro Std.parseFloat(${identifier()});

            case EConst(CIdent("SameFloatToInt")):
                macro Std.int(${identifier()});

            case _: 
                e.map(mapExpr.bind(ident, currentField));
        }
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

    static function createNew(type : Null<Type>, fromStructure : Expr) return switch type {
        case TInst(t, _) if(!t.get().meta.has(":structInit")):
            switch Context.toComplexType(type) {
                case TPath(p): macro new $p($fromStructure);
                case _: fromStructure;
            }
        case _: fromStructure;
    }

    static function extractTypeFromArray(type : Type) : Null<Type> {
        return switch type {
            case TLazy(f): extractTypeFromArray(f());
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
    
    #end
}
