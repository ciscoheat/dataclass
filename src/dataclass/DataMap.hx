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
    // The identifier used for the field. "person" in person.name
    final identifier : Expr;
    
    // All fields in the current object
    final fields : Array<ObjectField>;
    
    final currentType : Type;
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

    ///// Helpers ///////////////////////////////////////////////

    static function createNew(type : Type, structure : Expr) {
        return switch type {
            case TInst(t, _): 
                if(t.get().meta.has(":structInit")) structure
                else switch Context.toComplexType(type) {
                    case TPath(p): macro new $p($structure);
                    case _: Context.error("Invalid type for instantiation: " + type, Context.currentPos());
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

    static function returnTypeForField(type : Type, fieldName : String) : Option<Type> {
        function returnTypeInArray(type : Type) : Option<Type> {
            return switch type {
                case TLazy(f): returnTypeInArray(f());
                case TInst(t, params) if(t.get().name == "Array"): Some(params[0]);
                case _: None;
            }
        }
    
        return switch type {
            case TLazy(f): returnTypeForField(f(), fieldName);
            case TInst(t, _): 
                final field = t.get().fields.get().find(f -> f.name == fieldName);
                if(field == null) Context.error('Field not found on $type: ' + fieldName, Context.currentPos());
                else returnTypeInArray(field.type);

            case TAnonymous(a):
                final field = a.get().fields.find(f -> f.name == fieldName);
                if(field == null) Context.error('Field not found on $type: ' + fieldName, Context.currentPos());
                else returnTypeInArray(field.type);

            case _: 
                Context.error("Unsupported type for dataMap: " + type, Context.currentPos());
        }
    }

    // Map an expression for a field to the real expression
    static function mapField(info : DataClassInfo, fieldName : String, e : Expr) : Expr {
        function identifier(name) return {expr: EField(info.identifier, name), pos: e.pos};

        return switch e.expr {
            // Array comprehension for loops
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
                            Context.error("Unsupported for expression", e.pos);    
                    }                        
                    case _:
                        Context.error("Unsupported for expression", e.pos);
                }

            // Lambda functions on an Array field
            case EFunction(FArrow, f): 
                //trace('========== Function: $fieldName');
                if(f.expr == null) return Context.error("No object declaration in function", e.pos);

                // If no Array, ignore
                final returnType = switch f.expr.expr {
                    case EMeta(_, {expr: EReturn({expr: ENew(typePath, _), pos: _}), pos: _}): 
                        ComplexTypeTools.toType(TPath(typePath));
                    case _: 
                        switch returnTypeForField(info.currentType, fieldName) {
                            case Some(t): t;
                            case None:
                                return e.map(mapField.bind(info, fieldName));
                        }
                }

                final functionField = switch f.args.length {
                    case 1: fieldName;
                    case 2: f.args[1].name;
                    case _: Context.error("Unsupported arguments in lambda function", e.pos);
                }

                final forVar = f.args[0].name;
                final forIterate = identifier(functionField);

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
                final ident = identifier(fieldName);
                ident;

            case EConst(CIdent("SameString")):
                final ident = identifier(fieldName);
                macro Std.string($ident);

            case EConst(CIdent("SameInt")):
                final ident = identifier(fieldName);
                macro Std.parseInt($ident);

            case EConst(CIdent("SameFloat")):
                final ident = identifier(fieldName);
                macro Std.parseFloat($ident);

            case EConst(CIdent("SameFloatToInt")):
                final ident = identifier(fieldName);
                macro Std.int($ident);
    
            case _: 
                e.map(mapField.bind(info, fieldName));
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
                    e;
            }

            case _: e.map(mapSameForDisplay);
        }
    }

    static function mapDisplay(toStructure : Expr, expectedType : Type) {
        switch toStructure.expr {
            case EDisplay({expr: EBlock([]), pos: _}, DKStructure):
                switch Context.toComplexType(expectedType) {
                    case TPath(p):
                        final f = mapSameForDisplay({expr: EDisplay(macro {}, DKStructure), pos: Context.currentPos()});
                        return macro new $p($f);
                    case _:
                }
            case EDisplay({expr: EObjectDecl(fields), pos: _}, DKStructure):
                switch Context.toComplexType(expectedType) {
                    case TPath(p):
                        final f = mapSameForDisplay({expr: EDisplay({
                            expr: EObjectDecl(fields.map(f -> {expr: mapSameForDisplay(f.expr), field: f.field, quotes: f.quotes})),
                            pos: toStructure.pos
                        }, DKStructure), pos: Context.currentPos()});
                        return macro new $p($f);
                    case _:
                }    
            case _:
                //trace("----------- No match");
        }            
        toStructure.iter(e -> trace(Std.string(e.expr)));
        //trace(toStructure.toString());
        //trace("=========================");
        return mapSameForDisplay(toStructure);
    }

    #end

    public static macro function dataMap(from : Expr, toStructure : Expr, ?returns : Expr) {
        final expectedType = switch returns.expr {
            case EConst(CIdent("null")): switch toStructure.expr {
                case ENew(t, _): ComplexTypeTools.toType(TPath(t));
                case _: Context.getExpectedType();
            }
            case _: 
                Context.getType(returns.toString());
        }
        if(expectedType == null)
            Context.error("No return type found, please specify it.", Context.currentPos());

        if(Context.defined("display")) return mapDisplay(toStructure, expectedType);

        function toAnonField(e : Expr) return switch e.expr {
            case EObjectDecl(fields): 
                fields;
            case ENew(typePath, [{expr: EObjectDecl(fields), pos: _}]):
                fields;
            case _: 
                Context.error("Required: Anonymous object declaration or object instantiation.", e.pos);
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
