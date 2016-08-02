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

class DeepConverter implements DataClass
{
	@validate(_ > 10)
	public var int : Int;
	public var another : AnotherConverter;
}