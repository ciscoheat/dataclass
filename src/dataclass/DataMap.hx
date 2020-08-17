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
    static var isDynamic : Bool;

    public static macro function dataMap(from : Expr, to : Expr) {
        if(Context.defined("display")) return mapSameForDisplay(to);

        final expectedType = switch to.expr {
            case ENew(t, [{expr: EObjectDecl(_), pos: _}]): ComplexTypeTools.toType(TPath(t));
            case EObjectDecl(_): Context.getExpectedType();
            case _: null;
        }

        DataMap.isDynamic = try switch Context.typeof(from) {
            case TDynamic(_): true;
            case _: false;
        } catch(e : Dynamic) false;

        final output = if(expectedType != null)
            mapStructure(objectFields(to), from, expectedType)
        else
            mapExpr(from, null, to);

        //trace(output.toString());
        return output;
    }

    #if macro

    // Extract V in for(V in ...) or for(K => V in ...)
    static function extractForVar(e : Expr) return switch e.expr {
        case EConst(CIdent(s)) | EBinop(OpArrow, _, {expr: EConst(CIdent(s)), pos: _}):
            macro $i{s};
        case _:
            Context.error("Unsupported for expression", e.pos);
    }

    static function wrapForIterateIfDynamic(forIterate : Expr) 
        return switch forIterate.expr {
            case ECheckType(e, t): forIterate;
            case _ if(DataMap.isDynamic): macro ($forIterate : Iterable<Dynamic>);
            case _: forIterate;
        }

    // Map an expression for a field to the real expression
    static function mapField(from : Expr, fromType : Null<Type>, field : ObjectField) : Expr {     
        return switch field.expr.expr {

            // A bare for loop is transformed to array comprehension
            case EFor({expr: EBinop(OpIn, forVar, forIterate), pos: _}, forExpr):
                final ident = extractForVar(forVar);
                // Figure out if an object should be instantiated
                final forExpr = switch structureType(forExpr, fromType, field.field) {
                    case null: 
                        mapExpr(ident, field.field, forExpr);
                    case type: 
                        mapStructure(objectFields(forExpr), ident, extractTypeIfArray(type));
                }
                final forIterate = wrapForIterateIfDynamic(forIterate);

                macro [for($forVar in $forIterate) $forExpr];

            // A lambda function is transformed to array comprehension
            case EFunction(FArrow, func):                 

                final ident = macro $i{func.args[0].name};
                final functionField = switch func.args.length {
                    case 1: field.field;
                    case 2: func.args[1].name;
                    case _: Context.error("Unsupported number of arguments in lambda function.", func.expr.pos);
                }
                final forIterate = {expr: EField(from, functionField), pos: field.expr.pos};
                                
                switch func.expr.expr {
                    case EMeta(_, {expr: EReturn(e), pos: _}): 
                        final strType = structureType(e, fromType, field.field);
                        // Figure out if an object should be instantiated
                        final structure = switch strType {
                            case null: 
                                mapExpr(ident, field.field, e);
                            case type: 
                                mapStructure(objectFields(e), ident, extractTypeIfArray(type));
                        }
                        final forIterate = wrapForIterateIfDynamic(forIterate);

                        macro [for($ident in $forIterate) $structure];
        
                    case _: 
                        Context.error("Must be a lambda function.", func.expr.pos);
                }

            case _:
                mapExpr(from, field.field, field.expr);
        }
    }

    static function mapExpr(ident : Expr, currentField : Null<String>, e : Expr) {
        function identifier() {
            if(currentField == null) Context.error("Can only map fields using Same.", e.pos);
            return {expr: EField(ident, currentField), pos: ident.pos};
        }        

        return switch e.expr {
            case EFor({expr: EBinop(OpIn, forVar, forIterate), pos: _}, forExpr):
                final ident = extractForVar(forVar);
                final forIterate = wrapForIterateIfDynamic(forIterate);

                macro for($forVar in $forIterate) ${mapExpr(ident, currentField, forExpr)};

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

    static function extractTypeIfArray(arrayType : Type) : Null<Type> {
        return switch arrayType {
            case TLazy(f): extractTypeIfArray(f());
            case TInst(t, params) if(t.get().name == "Array"): params[0];
            case _: arrayType;
        }
    }

    // If e is a structure, return its type or try to derive it from its field.
    static function structureType(e : Expr, fromType : Null<Type>, fieldName : Null<String>) : Null<Type> {
        final output = switch e.expr {
            case ENew(typePath, [{expr: EObjectDecl(_), pos: _}]):
                ComplexTypeTools.toType(TPath(typePath));
            case EObjectDecl(_) if(fromType != null && fieldName != null): 
                returnTypeForField(fromType, fieldName);
            case _: null;
        }
        //trace('$fromType on field $fieldName: $output');
        return output;
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
