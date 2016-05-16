package subpack;
import dataclass.DataClass;

class AnotherConverter implements DataClass
{
	public var bool : Bool;
	public var int : Int;
	public var date : Date;
	public var float : Float;
}

class SubConverter implements DataClass
{
	public var bool : Bool;
	public var int : Int;
	public var date : Date;
	public var float : Float;	
}