import buddy.*;
import dataclass.*;
import haxe.DynamicAccess;
import haxe.Json;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.ds.Option;
import haxe.DynamicAccess;

#if js
import js.html.OptionElement;
import js.Browser;
#end

#if cpp
import hxcpp.StaticStd;
import hxcpp.StaticRegexp;
#end

using buddy.Should;

using dataclass.JsonConverter;
using dataclass.TypedJsonConverter;
using dataclass.CsvConverter;

abstract AInt(Int) to Int from Int {}
abstract AIntArray(Array<AInt>) to Array<Int> from Array<Int> {}

class AbstractTest implements DataClass 
{
    public var aint : AInt;
    public var aints : Array<AInt>;
	public var aaints : Array<Array<AInt>>;
	public var aintarray : AIntArray;
}

enum Color { Red; Blue; Rgb(r: Int, g: Int, b: Int); }

class RequireId implements DataClass
{
	// Not null, so id is required
	public var id : Int;
}

class AllowNull implements DataClass
{
	// Null value is ok
	public var name : Null<String>;
}

class DefaultValue implements DataClass
{
	// Default value set if no other supplied
	@validate(_.length > 0) public var city : String = "Nowhere";
	public var color : Color = Blue;
	public var date : Date = Date.now();
	public var status : HttpStatus = NotFound;
}

class Validator implements DataClass
{
	@validate(~/\d{4}-\d\d-\d\d/) public var date : String;
	@validate(_.length > 2 && _.length < 9) public var str : String;
	@validate(_.length > 0 && _[0] >= 100) public var integ : Array<Int>;
	public var ok : Bool = false;
}

class NullValidateTest implements DataClass
{
	// Field cannot be called "int" on flash!
	@validate(_ > 1000) public var integ : Null<Int>;
}

class OptionTest implements DataClass
{
	@validate(_ == "valid") public var str : Option<String>;
}

class OptionObjTest implements DataClass
{
	public var obj : Option<RequireId>;
}

interface IChapter extends DataClass
{
	@:validate(_.length > 0)
	public var info(default, set) : String;
}

class SimpleChapter implements IChapter
{
	public var info : String = 'simple info';
}

class ComplexChapter implements IChapter
{
	public var info : String = 'complex info';
	public var markdown : String;
}

interface Placeable {
	public var x : Float;
	public var y : Float;
}

class Place implements Placeable {
	public var x : Float;
	public var y : Float;
	public var name : String;
}

class Book implements DataClass {
	public var chapters : Array<IChapter>;
	public var name : String;
}

class DynamicAccessTest implements DataClass {
	public var email : String;

	@validate(_.get('test') != 0)
	public var info : DynamicAccess<Int> = {"test": 456};
	public var nullInfo : Null<haxe.DynamicAccess<Dynamic>>;
	public var moreInfo : DynamicAccess<Dynamic>;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

class Tests extends BuddySuite implements Buddy<[
	Tests, 
	InheritanceTests,
	#if (js && !nodejs)
	//HtmlFormConverterTests
	#end
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

#if !static_target
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
				it("should compile if all fields are null and nothing is passed to the constructor", {
					new AllowNull().name.should.be(null);
				});
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
				
				it("should fail validation if set to an invalid value", {
					var o = new DefaultValue();
					(function() o.city = "").should.throwType(String);
					(function() o.date = null).should.throwType(String);
				});
			});

			describe("With the Option type", {
				it("should validate the underlying value, not the Option object itself", {
					(function() new OptionTest({
						str: None
					})).should.throwType(String);

					(function() new OptionTest({
						str: null
					})).should.throwType(String);

					(function() new OptionTest({
						str: Some("invalid")
					})).should.throwType(String);

					var t = new OptionTest({str: Some("valid")});
					t.str.should.equal(Some("valid"));
				});

				it("should work for nested structures", {
					var id = new RequireId({id: 123});
					var o = new OptionObjTest({
						obj: Some(id)
					});
					var o2 = new OptionObjTest({
						obj: None
					});

					o.obj.should.equal(Some(id));
					o2.obj.should.equal(None);
				});
			});

			describe("With DynamicAccess", {
				it("should pass the data along untouched", {
					var test = new DynamicAccessTest({
						email: "test@example.com",
						info: cast {test: 123},
						moreInfo: cast {test: 234}
						//any: "ANY"
					});
					test.info.get('test').should.be(123);
					test.nullInfo.should.be(null);
					//(test.any : String).should.be("ANY");

					var test = new DynamicAccessTest({
						email: "test@example.com",
						nullInfo: cast {test: 789},
						moreInfo: cast {test: 234}
						//any: "ANY"
					});
					test.info.get('test').should.be(456);
					test.nullInfo.get('test').should.be(789);

					// Validation will fail for info.test
					(function() {
						new DynamicAccessTest({
							email: "test@example.com",
							info: cast {test: 0},
							moreInfo: cast {test: 234}
							//any: "ANY"
						});
					}).should.throwType(String);
				});
			});

			/*
			#if (haxe_ver >= 4)
			describe("With Immutable datastructures", {
				it("should work as expected", {
					var test = new DeepStateDSTest({
						array: ["A", "B", "C"],
						map: ["A" => 1],
						json: cast {test2: {test3: "ABC"}}
					});

					test.array[0].should.be("A");
					test.map["A"].should.be(1);
					test.json["test2"].get("test3").should.be("ABC");

					//trace(test.toJson());
				});
			});
			#end
			*/

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
				
				it("should not be possible to assign to def_null", {
					CompilationShould.failFor(
						new HasProperty({
							def_def: "A",
							def_null: "B",
							get_set: "C",
							get_null: "D"
						}).def_null = "assigned"
					);
				});
			});

			describe("With an existing constructor", {
				it("should inject the dataclass code at the top", {
					var prop2 = new IdWithConstructor({
						id: 1234,
						extra: "extraField"
					});
					
					// Set in constructor
					prop2.id.should.be(9876);
					prop2.initialId.should.be(1234);
					prop2.defaultParameter.should.be("ok");
					prop2.nullParameter.should.be(null);
					prop2.extra.should.be("extraField");
				});
			});

			describe("Abstract classes", {
				it("should resolve to the underlying type", {
					var abstr = new AbstractTest({
						aint: 123,
						aints: [123,456],
						aaints: [[123],[456]],
						aintarray: [1,2,3]
					});

					abstr.aint.should.be(123);
					
					abstr.aints.should.containExactly([123,456]);

					abstr.aaints.length.should.be(2);
					abstr.aaints[0].should.containExactly([123]);
					abstr.aaints[1].should.containExactly([456]);

					abstr.aintarray.should.containExactly([1,2,3]);
				});
			});

			describe("With @exclude on a public field", {
				it("should skip the field altogether", {
					var o2 = new ExcludeTest({ id: 123 });
					o2.input.should.be(null);
				});

				it("could still be assigned in a custom constructor", {
					var chapters : Array<IChapter> = [
						new SimpleChapter(), new ComplexChapter({markdown: '# Test'})
					];
					var book = new Book({
						name: 'The book',
						chapters: chapters,						
					}, new Place(10,20,"Test"));

					book.chapters.length.should.be(2);
					book.chapters[0].info.should.be("simple info");
					book.chapters[1].info.should.be("complex info");

					book.location.x.should.be(10);
				});
			});

			describe("With @include on a private field", {
				it("should include the field", {
					var o3 = new IncludeTest({ id: 123 });					
					o3.itsId().should.be(123);
					o3.notUsed.should.be("not used");
				});
			});

			describe("Validators", {
				it("should validate with @validate(...) expressions", {
					(function() new Validator({ date: "2015-12-12", str: "AAA", integ: [1001] })).should.not.throwAnything();
				});

				it("should validate regexps as a ^...$ regexp.", {
					(function() new Validator({	date: "*2015-12-12*", str: "AAA", integ: [1001] })).should.throwType(String);
				});

				it("should replace _ with the value and validate", {
					(function() new Validator({	date: "2015-12-12", str: "A", integ: [1001] })).should.throwType(String);
					(function() new Validator({	date: "2015-12-12", str: "AAA", integ: [1] })).should.throwType(String);
				});
				
#if !static_target
				it("should accept null values if field can be null", {
					new NullValidateTest({ integ: null }).integ.should.be(null);
					new NullValidateTest().integ.should.be(null);
					(function() new NullValidateTest( { integ: 1 } )).should.throwType(String);
					new NullValidateTest({ integ: 2000 }).integ.should.be(2000);
				});
#end

				it("should throw an exception when setting a var to an invalid value after instantiation", {
					var test = new NullValidateTest( { integ: 2000 } );
					test.integ.should.be(2000);
#if !static_target
					test.integ = null;
					test.integ.should.be(null);
#end
					test.integ = 3000;
					test.integ.should.be(3000);
					(function() test.integ = 100).should.throwType(String);
					test.integ.should.be(3000);
				});
			});
			
			describe("Manual validation", {
				it("should be done using the static 'validate' field", {
					Validator.validate({}).should.containAll(['date', 'str', 'integ']);
					Validator.validate({}).length.should.be(3);
					
					Validator.validate({ date: "2016-05-06" }).should.containAll(['str', 'integ']);
					Validator.validate( { date: "2016-05-06" } ).length.should.be(2);
					
					//var a = new Validator(
					
					var input = { integ: [1001], date: "2016-05-06", str: "AAA" };
					Validator.validate(input).length.should.be(0);
					
					RequireId.validate({}).should.contain("id");
					RequireId.validate({id: 1001}).length.should.be(0);
				});
				
				it("should fail a default value field if it exists but has an incorrect value", {
					HasProperty.validate({}).should.containAll(['def_null', 'def_def', 'get_set', 'get_null']);
					HasProperty.validate({}).length.should.be(4);
					
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
				it("should fail validation in constructor.", {
					(function() new ImmutableClass( { id: 456, name: "Test" } )).should.throwType(String);
				});

				it("should convert all var fields into (default, null) properties.", {
					CompilationShould.failFor(new ImmutableClass( { id: 123, name: "Test" } ).id = 456);
					CompilationShould.failFor(new ImmutableClass( { id: 123, name: "Test" } ).name = "Not a test");
				});

				#if (haxe_ver >= 4)
				it("should not be used with final keyword", {
					var immutable = new FinalClass({id: 123, name: "Test"});
					immutable.id.should.be(123);
					immutable.name.should.be("Test");
					(function() new FinalClass( { id: 456, name: "Test" } )).should.throwType(String);
				});
				#end
			});
		});
	}	
}

///////////////////////////////////////////////////////////////////////

class CurrencyData implements DataClass
{
	public var amount : Currency;
	public var amounts : Array<Currency>;
}

class DeepTest implements DataClass {
	public var id : String;
	public var single : DeepConverter;
	public var array : Array<ImmutableClass>;
	public var csv : Array<Array<String>>;
	@exclude public var unconvertable : Array<String -> Int>;
}

class OptionNoneTest implements DataClass
{
	public var str : Option<String>;
	public var assigned : Option<Int> = 9;
	public var abstr : Option<Array<AInt>> = [7];
}

class WrapUser implements DataClass {
    public var age : Int = 20;
    public var name : String;
}

class WrapWrapper implements DataClass {
    public var user : WrapUser;
    public var otherstuff : Array<String>;
}

///// Typed JSON tests /////

interface ITreeNode extends DataClass {
    public var id(default, set):String;
    public var children(default, set):Array<ITreeNode>;
}

class TreeBook implements ITreeNode {
    public var id : String = 'Book id';
    public var children : Array<ITreeNode> = [];

    public var bookSpecific: String = 'just for books';
}

// class TreeChapter is in subpack for testing purposes.

////////////////////////////////////////////////////////////////////////////////////////////////

/*
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
*/

class FinalDocument implements DataClass
{
	@validate(_ > -1) public final id : Int;
}

class FinalPerson extends FinalDocument
{
	@validate(_.length > 0) public final name : String;
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
		describe("When inheriting from a class with final fields", {
			it("should work as usual", {
				var p = new FinalPerson({id: 123, name: "Test"});
				p.id.should.be(123);
				p.name.should.be("Test");

				(function() new FinalPerson({id: -2, name: "Test"})).should.throwType(String);
			});
		});

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
			
			it("should set the parent fields when using the dynamic converter", {
				var data = {
					_key: "1",
					name: "Test Person",
					email: "test@example.com",
					notused: 123456
				};
				
				var p = SomePerson.fromJson(data);
				p.name.should.be("Test Person");
				p._key.should.be("1");
				p.email.should.be("test@example.com");
			});
		});
	}
}

#if (js && !nodejs)
/*
class HtmlFormConverterTests extends BuddySuite
{
	var date : js.html.InputElement;
	var str : js.html.InputElement;
	var integ : js.html.SelectElement;
	
	var conv : HtmlFormConverter;
	
	public function new() {
		beforeEach({			
			Browser.document.body.innerHTML = formHtml;
			date = cast Browser.document.querySelector("input[name=date]");
			str = cast Browser.document.querySelector("input[name=str]");
			integ = cast Browser.document.querySelector("select[name=integ]");
			
			cast(integ.options.item(1), OptionElement).selected = true;
			cast(integ.options.item(2), OptionElement).selected = true;
			date.value = "2016-05-08";
			str.checked = true;
			
			conv = new HtmlFormConverter(cast Browser.document.querySelector("form"));
		});
		
		describe("HtmlFormConverter", {
			it("should convert form fields into useful data structures", {
				var anon : Dynamic = conv.toAnonymousStructure();
				cast(anon.integ[0], String).should.be("100");
				cast(anon.integ[1], String).should.be("1001");
				anon.date.should.be("2016-05-08");
				anon.str.should.be("ab<cde");
				anon.ok.should.be("1");
				
				conv.toQueryString().should.be("date=2016-05-08&integ=100&integ=1001&ok=1&str=ab%3Ccde&submit=Submit");
			});
				
			it("should validate and convert to DataClass objects", {
				conv.validate(Validator).length.should.be(0);
				conv.toDataClass(Validator).integ.should.containExactly([100,1001]);
				conv.toDataClass(Validator).date.should.be("2016-05-08");
				conv.toDataClass(Validator).str.should.be("ab<cde");
				conv.toDataClass(Validator).ok.should.be(true);
			});
			
			it("should validate properly with failed fields", {
				cast(integ.options.item(1), OptionElement).selected = false;
				cast(integ.options.item(2), OptionElement).selected = false;
				conv.validate(Validator).length.should.be(1);
				conv.validate(Validator)[0].should.be("integ");
			});
		});
	}
	
	static var formHtml = '
<form>
	<input type="text" name="date">
	<select multiple name="integ">
		<option>10</option>
		<option>100</option>
		<option>1001</option>
	</select>
	<input type="hidden" name="ok" value="">
	<input type="checkbox" name="ok" value="1" checked>
	<input type="checkbox" name="str" value="ab&lt;cde">
	<input type="submit" name="submit" value="Submit"/>
</form>
';

	// Copy to index.html to test in browser
	static var testHtml = '
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8"/>
	<title>dataclass tests</title>
</head>
<body>
	<script src="js-browser.js"></script>
</body>
</html>	
';	
}
*/
#end
