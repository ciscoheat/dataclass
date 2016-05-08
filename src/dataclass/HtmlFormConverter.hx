package dataclass;

#if js
import haxe.Json;
import js.Browser;
import js.html.Element;
import js.html.ButtonElement;
import js.html.FormElement;
import js.html.InputElement;
import js.html.SelectElement;
import js.html.TextAreaElement;
import dataclass.Converter.DynamicObjectConverter;

using StringTools;

// Based on https://gist.github.com/brettz9/7147458
abstract HtmlFormConverter(FormElement) from FormElement {
	public inline function new(form : FormElement) this = form;
	
	@:from static public function fromElement(element : Element) {
		if (element == null) throw 'Element was null';
		if (!Std.is(element, FormElement)) throw 'You must supply a form element';
		return new HtmlFormConverter(cast element);
	}

	@:to public function toMap() : Map<String, String> {
		var map = new Map<String, String>();

		if (this == null || this.nodeName == null || this.nodeName.toLowerCase() != 'form')
			throw 'You must supply a form element';
		
		for (i in 0 ... this.elements.length) {
			var element : InputElement = cast this.elements[i];
			
			if (element.name.length == 0 || element.disabled) continue;

			switch element.nodeName.toLowerCase() {
				case 'input':
					var formElement : InputElement = cast element;
					switch formElement.type {
						// 'button isn't submitted when submitting form manually, though jQuery does serialize 
						// this and it can be an HTML4 successful control
						case 'text' | 'hidden' | 'password' | 'button' | 'submit' | // HTML5 next:
							 'search' | 'email' | 'url' | 'tel' | 'number' | 'range' | 'date' | 'month' | 
							 'week' | 'time' | 'datetime' | 'datetime-local' | 'color':							
							map.set(formElement.name, formElement.value);
						case 'checkbox' | 'radio':
							if (formElement.checked) map.set(formElement.name, formElement.value);
						case 'file':
							// Will work and part of HTML4 "successful controls", but not used in jQuery
							// map.set(formElement.name, formElement.value);
						case 'reset':
						case _:
							trace("Unknown form element type: " + formElement.type);
					}
					
				case 'textarea':
					var formElement : TextAreaElement = cast element;
					map.set(formElement.name, formElement.value);
					
				case 'select':
					var formElement : SelectElement = cast element;
					switch formElement.type {
						case 'select-one':
							map.set(formElement.name, formElement.value);
						case 'select-multiple':
							for (j in 0 ... formElement.options.length) {
								var select : SelectElement = cast formElement.options[j];
								if (Reflect.hasField(select, "selected")) {
									map.set(formElement.name, select.value);
								}
							}
					}
					
				case 'button': // jQuery does not submit these, though it is an HTML4 successful control
					var formElement : ButtonElement = cast element;
					switch formElement.type {
						case 'reset' | 'submit' | 'button':
							map.set(formElement.name, formElement.value);
					}
					
				case _:
					trace("Unknown form element: " + element.nodeName);
			}
		}
		return map;
	}

	@:to public function toAnonymous() : Dynamic {
		var map = toMap(), output = {};
		for (name in map.keys()) Reflect.setField(output, name, map.get(name));
		return output;
	}

	@:to public function toJson() : String return Json.stringify(toAnonymous());

	@:to public function toQueryString() : String {
		var map = toMap();
		return [for (name in map.keys()) name.urlEncode() + "=" + map.get(name).urlEncode()].join("&");
	}

	public function toDataClass<T : DataClass>(cls : Class<T>) : T {
		return DynamicObjectConverter.fromDynamic(cls, toAnonymous());
	}

	public function validate<T : DataClass>(cls : Class<T>, ?delimiter : String) : Array<String> {
		if (!Reflect.hasField(cls, "validate")) throw "No static validate method on class " + cls;
		var data = DynamicObjectConverter.convertToCorrectTypes(cls, toAnonymous(), delimiter);
		return untyped __js__('cls.validate({0})', data);
	}
}
#end
