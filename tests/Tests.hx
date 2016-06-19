import buddy.*;
import dataclass.*;
import haxe.DynamicAccess;
import haxe.Json;
import haxe.rtti.Meta;
import haxecontracts.ContractException;
import haxecontracts.HaxeContracts;

#if js
import js.Browser;
import js.html.DivElement;
import js.html.InputElement;
import js.html.OptionElement;
import js.html.SelectElement;
#end

#if cpp
import hxcpp.StaticStd;
import hxcpp.StaticRegexp;
#end

using StringTools;
using buddy.Should;
using dataclass.Converter;

enum Color { Red; Blue; }

class RequireId implements DataClass
{
	// Not null, so id is required
	public var id : Int;
}

class IdWithConstructor implements DataClass
{
	public var id : Int;
	@exclude public var initialId : Int;
	
	// Dataclass code will be injected before other things in the constructor.
	public function new(data) {
		// This value will be tested
		this.id = 9876;
		
		// Test if type is correct
		initialId = data.id;
	}
}

class AllowNull implements DataClass
{
	// Null value is ok
	public var name : Null<String>;
}

class DefaultValue implements DataClass
{
	// Default value set if no other supplied
	public var city : String = "Nowhere";
	public var color = Blue;
	public var date = Date.now();
}

class HasProperty implements DataClass
{
	@validate(_.length == 0)
	public var called : Array<String> = [];
	
	public var def_null(default, null) : String;

	public var def_def(default, default) : String;
	
	@validate(_.length == 1)
	public var get_set(get, set) : String;
	function set_get_set(v : String) {
		called.push("set_get_set");
		return _get_set = v;
	}
	function get_get_set() {
		called.push("get_get_set");
		return _get_set;
	}
	var _get_set : String;

	public var get_null(get, null) : String;
	function get_get_null() {
		called.push("get_get_null");
		return get_null;
	}
	
	public var def_null_defValue(default, null) : String = "def_null_defValue";
}

class HasPropertyWithImmutable implements DataClass implements Immutable
{
	public var def_null(default, null) : String;
	public var def_never(default, never) : String;
	public var def_never_defValue(default, never) : String = "def_never_defValue";
	public var def_null_defValue(default, null) : String = "def_null_defValue";
}

class Validator implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_ > 1000) public var int : Int;
}

class NullValidateTest implements DataClass
{
	@validate(_ > 1000) public var int : Null<Int>;
}

// Need @:keep to work in dce=full
@:keep class StringConverter implements DataClass
{
	public var date : String;
	public var bool : Bool;
	@validate(_ > 1000) public var int : Int;
	public var anything : String;
}

// Contains all types supported by the converter.
@:keep class TestConverter implements DataClass
{
	public var bool : Bool;
	public var int : Int;
	public var date : Date;
	public var float : Float;
}

@:keep class TestFloatConverter implements DataClass
{
	public var float : Null<Float>;
}

// Testing how convertTo reacts on a different type
@:keep class TestFakeFloatConverter implements DataClass
{
	public var float : String;
}

@:keep class TestColumnConverter implements DataClass
{
	@col(1) public var first : Int;
	@col(3) public var third : Bool;
	@col(2) public var second : Date;
	
	var internal : String;
}

class TestHaxeContracts implements DataClass implements HaxeContracts
{
	@validate(_ > 0) public var id : Null<Int>;
}

class ExcludeTest implements DataClass {
	public var id : Int;
	@exclude public var input : Array<Int>;
}

class IncludeTest implements DataClass {
	@include var id : Int;	
	public function itsId() return id;
	public var notUsed = "not used";
}

class ImmutableClass implements DataClass implements Immutable
{
	public var id : Int;
	public var name : String;	
}

interface ExtendingInterface extends DataClass
{
}

class Tests extends BuddySuite implements Buddy<[
	Tests, 
	ConverterTests, 
	#if (js && !nodejs)
	HtmlFormConverterTests,
	#end
	InheritanceTests
]>
{	
	public function new() {
		describe("DataClass", {
			describe("With non-null fields", {
				it("should not compile if non-null value is missing", {
					CompilationShould.failFor(new RequireId()).should.startWith("Not enough arguments");
					CompilationShould.failFor(new RequireId({})).should.startWith("Object requires field id");
					new RequireId( { id: 123 } ).id.should.be(123);
				});

#if !static
				it("should throw if null value is supplied", {
					(function() new RequireId({id: null})).should.throwType(String);
				});

				it("should throw an exception when setting the var to null after instantiation", {
					var id = new RequireId( { id: 123 } );
					(function() id.id = null).should.throwType(String);
				});
#end
			});

			describe("With null fields", {
				it("should compile if field value is missing", {
					new AllowNull({}).name.should.be(null);
				});
				it("should compile if null value is supplied as field", {
					new AllowNull({name: null}).name.should.be(null);
				});
			});
			
			describe("With default values", {				
				it("should be set to default if field value isn't supplied", {
					var now = Date.now();
					var o = new DefaultValue();
					
					o.city.should.be("Nowhere");
					o.color.should.equal(Color.Blue);
					o.date.should.not.be(null);
					(o.date.getTime() - now.getTime()).should.beLessThan(100);
				});
				it("should be set to the supplied value if field value is supplied", {
					new DefaultValue( { city: "Somewhere" } ).city.should.be("Somewhere");
				});				
			});

			describe("With property fields", {
				var prop : HasProperty;
				
				beforeEach({
					prop = new HasProperty({
						def_def: "A",
						def_null: "B",
						get_set: "C",
						get_null: "D"
					});
				});
				
				it("should be set as with var fields", {
					prop.def_def.should.be('A');
					prop.def_null.should.be('B');
					prop.get_set.should.be('C');
					prop.get_null.should.be('D');
					prop.def_null_defValue.should.be('def_null_defValue');
					
					prop.called.should.containAll(['set_get_set', 'get_get_set', 'get_get_null']);
				});
				
				it("should throw an exception when setting a property to an invalid value after instantiation", {
					(function() prop.get_set = "ABC").should.throwType(String);
				});				
			});

			describe("With an existing constructor", {
				it("should inject the dataclass code at the top", {
					var prop = new IdWithConstructor({
						id: 1234
					});
					
					// Set in constructor, below the dataclass code.
					prop.id.should.be(9876);
					prop.initialId.should.be(1234);
				});
			});

			describe("With @exclude on a public field", {
				it("should skip the field altogether", {
					var o = new ExcludeTest({ id: 123 });
					o.input.should.be(null);
				});
			});

			describe("With @include on a private field", {
				it("should include the field", {
					var o = new IncludeTest({ id: 123 });					
					o.itsId().should.be(123);
				});
			});

			describe("Validators", {
#if !php
				it("should validate with @validate(...) expressions", {
					(function() new Validator({ date: "2015-12-12", str: "AAA", int: 1001 })).should.not.throwAnything();
				});
#end

				it("should validate regexps as a ^...$ regexp.", {
					(function() new Validator({	date: "*2015-12-12*", str: "AAA", int: 1001 })).should.throwType(String);
				});

				it("should replace _ with the value and validate", {
					(function() new Validator({	date: "2015-12-12", str: "A", int: 1001 })).should.throwType(String);
					(function() new Validator({	date: "2015-12-12", str: "AAA", int: 1 })).should.throwType(String);
				});
				
#if !static
				it("should accept null values if field can be null", {
					new NullValidateTest({ int: null }).int.should.be(null);
					new NullValidateTest().int.should.be(null);
					(function() new NullValidateTest( { int: 1 } )).should.throwType(String);
					new NullValidateTest({ int: 2000 }).int.should.be(2000);
				});
#end

				it("should throw an exception when setting a var to an invalid value after instantiation", {
					var test = new NullValidateTest( { int: 2000 } );
					test.int.should.be(2000);
#if !static
					test.int = null;
					test.int.should.be(null);
#end
					test.int = 3000;
					test.int.should.be(3000);
					(function() test.int = 100).should.throwType(String);
					test.int.should.be(3000);
				});
			});
			
			describe("Manual validation", {
				it("should be done using the static 'validate' field", {
					Validator.validate({}).should.containAll(['date', 'str', 'int']);
					Validator.validate({}).length.should.be(3);
					
					Validator.validate({ date: "2016-05-06" }).should.containAll(['str', 'int']);
					Validator.validate( { date: "2016-05-06" } ).length.should.be(2);
					
					var input = { int: 1001, date: "2016-05-06", str: "AAA" };
					Reflect.setField(input, "int", 1001); // Required for flash, see https://github.com/HaxeFoundation/haxe/issues/5215
					Validator.validate(input).length.should.be(0);
					
					RequireId.validate({}).should.contain("id");
					RequireId.validate({id: 1001}).length.should.be(0);
				});
				
				it("should fail a default value field if it exists but has an incorrect value", {
					HasProperty.validate( { } ).should.containAll(['def_null', 'def_def', 'get_set', 'get_null']);
					HasProperty.validate( { } ).length.should.be(4);
					
					HasProperty.validate( { called: ["should fail"] } ).should.containAll(
						['called', 'def_null', 'def_def', 'get_set', 'get_null']
					);
					HasProperty.validate( { called: ["should fail"] } ).length.should.be(5);
				});
			});
			
			describe("Implementing HaxeContracts", {
				it("should throw ContractException instead of a string.", {				
					(function() new TestHaxeContracts({ id: -1 })).should.throwType(ContractException);
				});
			});
			
			describe("Using the @immutable metadata", {
				it("should convert all var fields into (default, null) properties.", {
					// Difficult to test compilations errors...!
					var immutable = new ImmutableClass({ id: 123, name: "Test" });
					immutable.should.beType(ImmutableClass);
					
					//immutable.id = 456;
					immutable.id.should.be(123);
					immutable.name.should.be("Test");					
				});
			});
		});

		describe("DataClass conversions", {
			it("should convert Dynamic to the correct type.", {
				var data = {
					date: "2015-12-12",
					bool: "1",
					int: "2000",
					doesNotExist: "should not be added",
					anything: { test: 123 }
				};
				
				var a = StringConverter.fromDynamic(data);
				
				a.date.should.be("2015-12-12");
				a.bool.should.be(true);
				a.int.should.be(2000);
				Reflect.hasField(a, "doesNotExist").should.be(false);
				a.anything.should.match(~/\{\s*test\b.+\b123\s*\}/);
			});

			it("should fail unless validated.", {
				var data = Json.parse('{
					"date": "2015-12-12",
					"bool": "1",
					"int": "100",
					"anything": "123"
				}');
				
				#if cs
				try {
					StringConverter.fromDynamic(data);
					fail("Object should fail validation.");
				} catch (e : Dynamic) {
					e.should.not.be(null);
				}
				#else
				(function() StringConverter.fromDynamic(data)).should.throwType(String);
				#end
			});
			
			it("should parse floats correctly", {
				var data = { float: "123345.44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);
			});
			
			it("should parse Int and Float to Date", {
				var a = TestConverter.fromDynamic({
					date: 1466302574606,
					bool: "1",
					int: "2000",
					float: "123.45"
				});
				
				var b = TestConverter.fromDynamic({
					date: 1466302574606.01,
					bool: "1",
					int: "2000",
					float: "123.45"
				});
				
				a.date.toString().should.match(~/^2016-06-1[89] \d\d:16:14$/);
				b.date.toString().should.match(~/^2016-06-1[89] \d\d:16:14$/);
			});
			
			it("should parse money format correctly", {
				var old = Converter.delimiter;
				Converter.delimiter = ",";
				
				var data = { float: "$123.345,44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);
				
				Converter.delimiter = old;
			});
			
			it("should parse column data when using the @col metadata", {
				var data = ["123", "2015-01-01", "1"];
				var obj = TestColumnConverter.fromColMetaData(data);
				
				obj.first.should.be(123);
				obj.second.toString().should.be("2015-01-01 00:00:00");
				obj.third.should.be(true);
			});

			it("should parse column data when using an array of columns", {
				var data = ["123", "2015-01-01", "1"];
				var columns = ["first", "second", "third"];
				var obj = TestColumnConverter.fromColumnData(columns,data);
				
				obj.first.should.be(123);
				obj.second.toString().should.be("2015-01-01 00:00:00");
				obj.third.should.be(true);
			});

			it("should convert public fields to the specified string format.", {
				var a = TestConverter.fromDynamic({
					date: "2015-12-12",
					bool: "1",
					int: "2000",
					float: "123.45"
				});
				
				var o = a.toStringData({
					delimiter: ',',
					boolValues: { tru: "YES", fals: "NO" },
					dateFormat: "%Y%m%d"
				});
				
				Reflect.fields(o).length.should.be(4);
				a.float.should.be(123.45);
				o.date.should.be("20151212");
				o.bool.should.be("YES");
				o.int.should.be("2000");
				o.float.should.be("123,45");
			});
			
			it("should auto-detect delimiter if set to an empty string", {
				var old = Converter.delimiter;
				Converter.delimiter = "";
				
				var data = { float: "$123.345,44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);

				data = { float: "123 345.44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);

				data = { float: "123345,44" };
				TestFloatConverter.fromDynamic(data).float.should.beCloseTo(123345.44);

				Converter.delimiter = old;				
			});
		});		
	}	
}

class ConverterTests extends BuddySuite
{	
	public function new() {
		describe("Converter", {
			var test : TestConverter;
			
			beforeEach({
				var data = {
					bool: "true".toBool(),
					int: "123".toInt(),
					date: "2015-01-01 00:00:00".toDate(),
					float: "456.789".toFloat()
				};
				
				test = new TestConverter(data);
			});
			
			it("should work with the supported types", {
				test.bool.should.be(true);
				test.int.should.be(123);
				DateTools.format(test.date, "%Y-%m-%d %H:%M:%S").should.be("2015-01-01 00:00:00");
				test.float.should.beCloseTo(456.789, 3);
				
				test.bool.toString({tru: "YES", fals: "NO"}).should.be("YES");
				(false).toString({tru: "YES", fals: "NO"}).should.be("NO");
				
				test.int.toString().should.be("123");
				test.date.toStringFormat("%Y-%m-%d").should.be("2015-01-01");
				test.float.toString().should.be("456.789");				
			});
			
			it("should be able to assign a number of fields in one operation", {
				var date = new Date(2016, 4, 15, 0, 0, 0);
				var other = {
					bool: false,
					float: -20.05
				};
				
				test.assignFromVars(date, other.bool, other.float);
				
				test.bool.should.be(false);
				test.date.toStringFormat("%Y-%m-%d").should.be("2016-05-15");
				test.float.should.beCloseTo(-20.05);
			});

			it("should be able to create a DataClass from local vars", {
				var date = new Date(2016, 4, 15, 0, 0, 0);
				var other = {
					bool: false,
					float: -20.05,
					int: 123
				};
				
				// Adding a subpackage to test the conversion
				var test = subpack.AnotherConverter.createFromVars(date, other.bool, other.float, other.int);				
				test.bool.should.be(false);
				test.int.should.be(123);
				test.date.toStringFormat("%Y-%m-%d").should.be("2016-05-15");
				test.float.should.beCloseTo( -20.05);

				var test2 = TestConverter.createFromVars(date, other.bool, other.float, other.int);
				test2.bool.should.be(false);
				test2.int.should.be(123);
				test2.date.toStringFormat("%Y-%m-%d").should.be("2016-05-15");
				test2.float.should.beCloseTo( -20.05);
				
				// Test using the static method (no extension)
				var test3 = Converter.createFromVars(TestConverter, date, other.bool, other.float, other.int);
				test3.bool.should.be(false);
				test3.int.should.be(123);
				test3.date.toStringFormat("%Y-%m-%d").should.be("2016-05-15");
				test3.float.should.beCloseTo( -20.05);
				
				var test4 = Converter.createFromVars(subpack.AnotherConverter.SubConverter, date, other.bool, other.float, other.int);
				test4.bool.should.be(false);
				test4.int.should.be(123);
				test4.date.toStringFormat("%Y-%m-%d").should.be("2016-05-15");
				test4.float.should.beCloseTo( -20.05);
			});

			it("should be able to create one object from another", {
				var testFloat = test.convertTo(TestFloatConverter);				
				Std.is(testFloat, TestFloatConverter).should.be(true);
				testFloat.float.should.beCloseTo(456.789, 3);
				
				var ex = (function() test.convertTo(Validator)).should.throwType(String);
				ex.indexOf("Validator").should.beGreaterThan( -1);
				
				var fakeFloat = new TestFakeFloatConverter( { float: "not a float..." } );
				var testFloat2 = fakeFloat.convertTo(TestFloatConverter);
				testFloat2.float.toString().should.be(Math.NaN.toString());
			});
			
			it("should convert all public dataclass fields of an object to an anonymous structure", {
				// Using IncludeTest since it has a private var that is included in the constructor data
				var test = new IncludeTest({id: 123});
				var output : DynamicAccess<Dynamic> = test.toAnonymousStructure();
				
				output.keys().length.should.be(1);
				output.get("notUsed").should.be("not used");
				
				var output2 : DynamicAccess<String> = test.toStringData();
				output2.keys().length.should.be(1);
				output2.get("notUsed").should.be("not used");
			});
		});
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////

class Document
{
	@ignore public var _id(default, null) : Null<String>;
	@validate(_ == null || _.length > 0) public var _key(default, set) : Null<String>;
	public var _rev(default, null) : Null<String>;
	
	function set__key(v : String) {
		#if !python
		// Possibly python compilation bug:
		// AttributeError("'SomePerson' object has no attribute '_key'",)
		if (_key != null) throw '_key already exists: $_key';
		#end
		if (v == null) throw '_key cannot be null';
		return _key = v;
	}
}

// SomePerson should now include the _key attribute.
class SomePerson extends Document implements DataClass
{
	@validate(_.length > 0) public var name : String;
	@validate(_.indexOf("@") > 0) public var email : String;
}

class InheritanceTests extends BuddySuite
{
	public function new() {
		describe("When inheriting from another class", {
			it("should required the public and @included fields in the constructor", {
				var p = new SomePerson({
					_key: "1",
					name: "Test Person",
					email: "test@example.com"
				});

				p.name.should.be("Test Person");
				p._key.should.be("1");
				#if !python
				(function() p._key = "2").should.throwType(String);
				#end
				(function() p._key = null).should.throwType(String);
			});
		});
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////

#if (js && !nodejs)
class HtmlFormConverterTests extends BuddySuite
{
	var date : InputElement;
	var str : InputElement;
	var int : SelectElement;
	
	var conv : HtmlFormConverter;
	
	public function new() {
		beforeEach({			
			Browser.document.getElementById("tests").innerHTML = formHtml;
			date = cast Browser.document.querySelector("input[name=date]");
			str = cast Browser.document.querySelector("input[name=str]");
			int = cast Browser.document.querySelector("select[name=int]");
			
			int.selectedIndex = 2;
			date.value = "2016-05-08";
			str.checked = true;
			
			conv = Browser.document.querySelector("form");
		});
		
		describe("HtmlFormConverter", {
			it("should convert form fields into useful data structures", {				
				var anon : Dynamic = conv.toAnonymous();
				anon.int.should.be("1001");
				anon.date.should.be("2016-05-08");
				anon.str.should.be("ab<cde");
				
				var map = conv.toMap();
				map.get('int').should.be("1001");
				map.get('date').should.be("2016-05-08");
				map.get('str').should.be("ab<cde");
				
				conv.toJson().should.be('{"date":"2016-05-08","int":"1001","str":"ab<cde","submit":"Submit"}');
				conv.toQueryString().should.be("date=2016-05-08&int=1001&str=ab%3Ccde&submit=Submit");
				
				Validator.fromDynamic(conv).int.should.be(1001);
				Validator.fromDynamic(conv).date.should.be("2016-05-08");
				Validator.fromDynamic(conv).str.should.be("ab<cde");
			});
				
			it("should validate and convert to DataClass objects", {
				conv.validate(Validator).length.should.be(0);
				conv.toDataClass(Validator).int.should.be(1001);
				conv.toDataClass(Validator).str.should.be("ab<cde");
			});
			
			it("should validate properly with failed fields", {
				int.selectedIndex = 0;
				conv.validate(Validator).length.should.be(1);
				conv.validate(Validator)[0].should.be("int");
			});
		});
	}
	
	static var formHtml = '
<form>
	<input type="text" name="date">
	<select name="int">
		<option>10</option>
		<option>100</option>
		<option>1001</option>
	</select>
	<input type="checkbox" name="str" value="ab&lt;cde">
	<input type="submit" name="submit" value="Submit"/>
</form>
';

	static var testHtml = '
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8"/>
	<title>dataclass tests</title>
</head>
<body>
	<script src="js-browser.js"></script>
	<div id="tests"></div>
</body>
</html>	
';	
}
#end
