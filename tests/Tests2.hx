import buddy.*;
import dataclass.*;
import haxe.DynamicAccess;
import haxe.Json;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.ds.Option;
import haxe.DynamicAccess;
import dataclass.DataMap.dataMap;

#if js
import js.html.OptionElement;
import js.Browser;
#end

using buddy.Should;
using Dataclass2;
//using dataclass.DataMap;

/////////////////////////////////////////////////////////////////////

abstract AInt(Int) to Int from Int {}
abstract AIntArray(Array<AInt>) to Array<Int> from Array<Int> {}

@:publicFields class AbstractTest implements DataClass 
{
    final aint : AInt;
    final aints : Array<AInt>;
	final aaints : Array<Array<AInt>>;
	final aintarray : AIntArray;
}

@:enum abstract HttpStatus(Int) {
	var NotFound = 404;
	var MethodNotAllowed = 405;
}

enum Color { Red; Blue; Rgb(r: Int, g: Int, b: Int); }

class RequireId implements DataClass
{
	// Not null, so id is required
	public final id : Int;
}

class AllowNull implements DataClass
{
	// Null value is ok
	public final name : Null<String>;
}

class DefaultValue implements DataClass
{
	// Default value set if no other supplied
	@:validate(_.length > 0) public final city : String = "Nowhere";
	public final color : Color = Blue;
	@:validate(_.getFullYear() >= 2020)
	public final date : Date = Date.now();
	public final status : HttpStatus = NotFound;
}

@:publicFields class Validator implements DataClass
{
	@:validate(~/^\d{4}-\d\d-\d\d$/) final date : String;
	@:validate(_.length > 2 && _.length < 9) final str : String;
	@:validate(_.length > 0 && _[0] >= 100) final integ : Array<Int>;
	final ok : Bool = false;
}

class NullValidateTest implements DataClass
{
	// Field cannot be called "int" on flash!
	@:validate(_ > 1000) public final integ : Null<Int>;

	public var isLarge(get, never) : Bool;
	function get_isLarge() return integ >= 1000000;
}

@:publicFields class TrimModifierTest implements DataClass
{
	@:trim @:validate(_ == "trimmed")
	final str : String;
	
	@:validate(_ == null || _ == "nullable")
	@:trim final nullable : Null<String>;
}

interface IChapter extends DataClass
{
	@:validate(_.length > 0)
	public final info : String;
}

class SimpleChapter implements IChapter
{
	public final info : String = 'simple info';
}

class ComplexChapter implements IChapter
{
	public final info : String = 'complex info';
	public final markdown : String;
}

interface Placeable {
	public final x : Float;
	public final y : Float;
}

class Place implements DataClass implements Placeable {
	public final x : Float;
	public final y : Float;
	public final name : String;
}

class Book implements DataClass {
	public final chapters : Array<IChapter>;
	public final name : String;
}

class DynamicAccessTest implements DataClass {
	public final email : String;

	@:validate(_.get('test') != 0)
	public final info : DynamicAccess<Int> = {"test": 456};
	public final nullInfo : Null<haxe.DynamicAccess<Dynamic>>;
	public final moreInfo : DynamicAccess<Dynamic>;
}

enum Content {
	X; O; No;
}

class Tile implements DataClass {
	@:validate(!_.equals(No))
	public final content : Content;
}

class WishItemData implements DataClass {
    static final item_price_max : Int = 20;

    @:validate(_ > 0 && _ <= item_price_max)
    public final item_price:Float;
}

class DataclassContainer implements DataClass {
	public final item : WishItemData;
	public final id : Int;
}

/*
// This should fail due to a validator on a static field.
class WillFail implements DataClass {
	@:validate(_ == 20)
    static final item_price_max : Int = 20;

    @:validate(_ > 0 && _ <= item_price_max)
    public final item_price:Float;
}
*/

// This should fail due to a property with non-allowed accessors
/*
class WillFail implements DataClass {
	public final test : Float;
	
	public var test2(default, null) : Int;
}
*/

///////////////////////////////////////////////////////////////////////////////

class Tests2 extends BuddySuite implements Buddy<[
	Tests2,
	InheritanceTests
]>
{	
	public function new() {
		describe("DataClass", {
			it("Should instantiate", {
				//try {
					final test = new Dataclass2({
						id: 123,
						email: "test@example.com",
						city: "Punxuatawney",
						active: false
					});
					test.id.should.be(123);
					test.avoidNull.should.equal(None);
					test.status.should.be(NotFound);

					final test2 = test.copy();
					test2.id.should.be(123);
					test2.avoidNull.should.equal(None);
					test2.status.should.be(NotFound);

					final test3 = Dataclass2.copy(test2, {id: 234});
					test3.id.should.be(234);
					test3.avoidNull.should.equal(None);
					test3.status.should.be(NotFound);

					(function() new Dataclass2({
						id: 123,
						email: "test@example.com",
						city: "Punxuatawney",
						active: true,
						status: MethodNotAllowed
					})).should.throwType(DataClassException);
				//} catch(e : DataClassException<Dynamic>) trace(e.errors);
			});

			it("Should work according to the concept class", {
				final test = new Dataclass2({
					id: 123,
					email: "test@example.com",
					city: "Punxuatawney",
					avoidNull: Some("value"),
					active: false
				});
				test.active.should.be(false);
				test.avoidNull.should.equal(Some("value"));
				test.yearCreated().should.beGreaterThan(2018);

				#if js
				// js can JSONify enums directly
				final json = Json.stringify(test, "	");	
				final data2 : Dynamic = Json.parse(json);
				final test2 = new Dataclass2(data2);
				test2.yearCreated().should.beGreaterThan(2018);
				test2.avoidNull.should.equal(Some("value"));
				test2.status.should.be(NotFound);
				#end

				try {
					new Dataclass2({
						id: 0,
						email: "no email",
						city: "X"
					});
					fail("Validation should fail here.");
				} catch(e : DataClassException) {
					e.errors.get('id').should.equal(Some(0));
					e.errors.get('city').should.equal(Some("X"));
				}
			});

			it("should validate Enums", {
				final test = new Tile({content: X});
				test.content.should.equal(X);

				try new Tile({content: No})
				catch(e : DataClassException) {
					e.errors.get('content').should.equal(Some(No));
				}
			});

			it("should work with static fields without validators", {
				new WishItemData({item_price: 12.34}).should.not.be(null);
			});

			it("should be compatible with deep_equal", {
				final test1 = new DataclassContainer({
					item: new WishItemData({item_price: 10}),
					id: 123
				});

				final test2 = new DataclassContainer({
					item: new WishItemData({item_price: 10}),
					id: 123
				});

				Std.string(deepequal.DeepEqual.compare(test1, test2)).should.startWith("Success");
			});

			///////////////////////////////////////////////////////////////////

			describe("With non-null fields", {
				it("should not compile if non-null value is missing", {
					CompilationShould.failFor(new RequireId());
					CompilationShould.failFor(new RequireId({}));
					new RequireId( { id: 123 } ).id.should.be(123);
				});

#if !(cpp || java || flash || cs || hl)
				it("should throw if null value is supplied", {
					(function() new RequireId({id: null})).should.throwType(DataClassException);
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
					(function() DefaultValue.copy(o, {city: ""})).should.throwType(DataClassException);
				});
			});

			describe("With DynamicAccess", {
				it("should pass the data along untouched", {
					var test = new DynamicAccessTest({
						email: "test@example.com",
						info: cast {test: 123},
						moreInfo: cast {test: 234}
					});
					test.info.get('test').should.be(123);
					test.nullInfo.should.be(null);
					//(test.any : String).should.be("ANY");

					var test = new DynamicAccessTest({
						email: "test@example.com",
						nullInfo: cast {test: 789},
						moreInfo: cast {test: 234}
					});
					test.info.get('test').should.be(456);
					test.nullInfo.get('test').should.be(789);

					// Validation will fail for info.test
					(function() {
						new DynamicAccessTest({
							email: "test@example.com",
							info: cast {test: 0},
							moreInfo: cast {test: 234}
						});
					}).should.throwType(DataClassException);
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
					//abstr.aintarray.should.containExactly([1,2,3]);

					abstr.aaints.length.should.be(2);
					abstr.aaints[0].should.containExactly([123]);
					abstr.aaints[1].should.containExactly([456]);

				});
			});

			describe("Validators", {
				it("should validate with @validate(...) expressions", {
					(function() new Validator({ date: "2015-12-12", str: "AAA", integ: [1001] })).should.not.throwAnything();
				});

				it("should validate regexps", {
					(function() new Validator({	date: "*2015-12-12*", str: "AAA", integ: [1001] })).should.throwType(DataClassException);
				});

				it("should replace _ with the value and validate", {
					(function() new Validator({	date: "2015-12-12", str: "A", integ: [1001] })).should.throwType(DataClassException);
					(function() new Validator({	date: "2015-12-12", str: "AAA", integ: [1] })).should.throwType(DataClassException);
				});
			});	

			describe("Manual validation", {
				it("should be done using the static 'validate' field", {
					CompilationShould.failFor(Validator.validate({}));
					CompilationShould.failFor(Validator.validate({ date: "2016-05-06" }));
					
					var errors = Validator.validate({ integ: [1001], date: "2016-05-06", str: "AAA" });
					errors.should.equal(None);

					var errors2 = Validator.validate({ integ: [1001], date: "0000", str: "AAA" });
					switch errors2 {
						case None: fail('Should be errors.');
						case Some(error): 
							switch error.get("date") {
								case None: fail('Should be date error.');
								case Some(v): v.should.be("0000");
							}
					}
				});	
				
				it("should be possible to validate just one field with the static validate methods", {
					Validator.validateDate("2020-07-22").should.be(true);
					Validator.validateDate("x").should.be(false);
					Validator.validateInteg([200, 300]).should.be(true);

					Tile.validateContent(X).should.be(true);
					Tile.validateContent(No).should.be(false);

					DefaultValue.validateDate(Date.fromString("2019-01-01")).should.be(false);
					DefaultValue.validateDate(Date.fromString("2020-01-01")).should.be(true);
				});
			});

			describe("Properties", {
				it("only properties with 'get, never' accessors are allowed", {
					final n = new NullValidateTest({integ: 11000000});
					n.isLarge.should.be(true);
				});
			});

			describe("Modifying metadata", {
				it("should be possible to trim fields with @:trim metadata", {
					final f = new TrimModifierTest({
						str: " trimmed  ",
						nullable: "nullable"
					});

					f.str.should.be("trimmed");
					f.nullable.should.be("nullable");
				});

				it("should handle null values when using @:trim", {
					final f = new TrimModifierTest({
						str: " trimmed  ",
						nullable: null
					});

					f.str.should.be("trimmed");
					f.nullable.should.be(null);
				});
			});
		});

		/////////////////////////////////////////////////////////////

		describe("DataMap", {
			final customer : ProgramViewPerson = {
				_id: 1,
				name: "TestCustomer",
				programs: [{
					name: "TestProg",
					sets: [{
						_id: 2,
						selected: false,
						reps: "0",
						exercises: [{
							sets: "3",
							reps: "3",
							extrainfo: "",
							exerciseTemplateId: 10
						}]
					}]
				}]
			}

			it("should use a brief syntax to map Dataclass objects.", {
				final test = new DataMapTest();

				Std.string(deepequal.DeepEqual.compare(
					test.toCustomer(customer), test.toCustomerGold(customer)
				)).should.startWith("Success");
			});

			final set = new SuperSet({
				_id: 1,
				reps: 0,
				exercises: [new Exercise({
					sets: 1, reps: "2", extrainfo: "", exerciseTemplateId: 2
				})]
			});

			it("should handle :structInit classes", {
				final superSet = new DataMapTest().toSuperSet(set);

				superSet.should.beType(ProgramViewSuperSet);
				superSet.exercises[0].should.beType(ProgramViewExercise);
				superSet.selected.should.be(false);
				superSet.exercises[0].reps.should.be("2");
			});

			it("should handle anonymous structures", {
				final idSet = new DataMapTest().toAnonStructure(set);
				idSet._id.should.be(1);
			});

			it("should cast all for loops to Iterable<Dynamic> when using Dynamic", {
				final c = new DataMapTest().jsonToCustomer(customer);				
				c.should.beType(Customer);

				final e = c.programs[0].supersets[0].exercises[0];
				e.should.beType(Exercise);
				e.exerciseTemplateId.should.be(10);
			});

			it("should handle any other expression", {
				final superSet = new DataMapTest().toArray(set);
				superSet.should.containExactly(["2"]);
			});
		});
	}	
}

///// DataMap /////////////////////////////////////////////////////////////////

class DataMapTest
{
	public function new() {}

	// Autocomplete test method

	/*
	public function toCustomerAutocomplete(person : ProgramViewPerson) {
		return dataMap(person, new Customer({			
			name: Same,
			programs: for(p in person.programs) {				
				name: Same,
				supersets: new SuperSet({})
			}
		}));
	}
	*/

	public function toArray(set : SuperSet) {
		return dataMap(set, [for(m in set.exercises) m.reps]);
	}

	public function toAnonStructure(set : SuperSet) {
		return dataMap(set, {
			_id: Same
		});
	}

	public function toSuperSet(set : SuperSet) {
		final set : ProgramViewSuperSet = DataMap.dataMap(set, {
			_id: Same,
			selected: false,
			reps: Std.string(Same),
			exercises: e -> new ProgramViewExercise({
				sets: SameString,
				reps: Same,
				extrainfo: Same,
				exerciseTemplateId: Same
			})
		});
		return set;
	}

	public function toCustomer(person : ProgramViewPerson) : Customer {
		return dataMap(person, {
			_id: Same,
			name: Same,
			programs: p -> {
				name: Same,
				map: [for(s in ["A", "B", "C"]) s => p.name],
				supersets: for(s in p.sets) {
					_id: s._id,
					reps: SameInt,
					exercises: e -> {
						final x = 0;
						new Exercise({
							sets: Std.parseInt(Same) + x,
							reps: Same,
							extrainfo: Same,
							exerciseTemplateId: Same
						});
					}
				}
			}
		});
	}

    public function toCustomerGold(person : ProgramViewPerson) {
        return new Customer({
            _id: person._id,
            name: person.name,
            programs: [for(p in person.programs) new Program({
				name: p.name,
				map: [for(s in ["A", "B", "C"]) s => p.name],
                supersets: [for(s in p.sets) new SuperSet({
                    _id: s._id,
                    reps: Std.parseInt(s.reps),
                    exercises: [for(e in s.exercises) new Exercise({
                        sets: Std.parseInt(e.sets),
                        reps: e.reps,
                        extrainfo: e.extrainfo,
                        exerciseTemplateId: e.exerciseTemplateId
                    })]
                })]
            })]
        });
	}
	
    public function jsonToCustomer(json : Dynamic) : Customer
        return dataMap(json, new Customer({
            _id: Same,
            name: Same,
            programs: p -> new Program({
				name: Same,
				map: [],
                supersets: for(s in (p.sets : Array<SuperSet>)) new SuperSet({
                    _id: Same,
                    reps: Same,
                    exercises: e -> new Exercise(e)
                })
            })
        }));
}

@:publicFields @:structInit private class ProgramViewSuperSet {
    final _id : Int;
    var selected : Bool;
    var reps : String;
    final exercises : Array<ProgramViewExercise> = [];
}

@:publicFields @:structInit private class ProgramViewExercise {
    var sets : String;
    var reps : String;
    var extrainfo : String;
    final exerciseTemplateId : Int;
}

@:publicFields @:structInit private class ProgramViewProgram {
    var name : String;
    final sets : Array<ProgramViewSuperSet> = [];
}

@:publicFields @:structInit private class ProgramViewPerson {
    final _id : Int;
    var name : String; 
    final programs : Array<ProgramViewProgram> = [];
}

/////

@:publicFields class Customer implements DataClass
{   
    final _id : Int;
    @:validate(_.length > 0)
    final name : String;
 //   final email : String;
 //   final phone : String;
    final programs : Array<Program> = [];
}

@:publicFields class Program implements DataClass
{   
 //   final _id : Int;
    final name : String;
	final map : Map<String, String>;
	final supersets : Array<SuperSet> = []; 
}

@:publicFields class SuperSet implements DataClass
{
    private static var idCount = 0;
    public static function nextId() return ++idCount;

    final _id : Null<Int>;

    @:validate(_ == 0 || _ >= 2)
    final reps : Int;

    final exercises : Array<Exercise> = [];

    function new(data) {
        if(reps == 0 && exercises.length != 1)
            throw "Too many exercises";
        else if(reps > 0 && exercises.length < 2)
            throw "Too few exercises";

        if(_id == null) _id = nextId();
    }
}

@:publicFields class Exercise implements DataClass 
{
 //   final _id : Int;
    final sets : Int;
    final reps : String;    
    final extrainfo : String;
    final exerciseTemplateId : Int;
}

/////

///////////////////////////////////////////////////////////////////////////////

@:publicFields class Document implements DataClass
{
	@:exclude final _id : Null<String>;
	@:validate(_ == null || _ > 0) final _key : Null<Int>;

	public function new(data) {
		this._id = _key != null ? 'ID:$_key' : "NO-ID";
	}
}

class Person extends Document
{
	@:trim @:validate(_.length > 0) public final name : String;
}

class InheritanceTests extends BuddySuite
{
	public function new() {
		describe("When inheriting from a class with a constructor", {
			it("should inject the dataclass constructor before the expressions", {
				var p = new Person({_key: 123, name: " Test"});
				p._key.should.be(123);
				p.name.should.be("Test");
				p._id.should.be("ID:123");

				(function() new Person({_key: -2, name: "Test"})).should.throwType(DataClassException);
			});
		});
	}
}