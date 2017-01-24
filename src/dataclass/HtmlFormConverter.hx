package dataclass;
import js.Lib;
import js.html.OptionElement;

#if js
import haxe.CallStack;
import haxe.DynamicAccess;
import haxe.Json;

import js.Browser;
import js.html.Element;
import js.html.ButtonElement;
import js.html.FormElement;
import js.html.InputElement;
import js.html.SelectElement;
import js.html.TextAreaElement;

import dataclass.CsvConverter.CsvConverterOptions;

using StringTools;

// Based on https://gist.github.com/brettz9/7147458
class HtmlFormConverter
{
	var element : FormElement;
	var converter : CsvConverter;
	
	public function new(element : Element, ?options : CsvConverterOptions) {
		if (element == null || element.nodeName == null || element.nodeName.toLowerCase() != 'form')
			throw 'You must supply a form element.';
		
		this.element = cast element;
		this.converter = new CsvConverter(options);		
	}
	
	public function toAnonymousStructure() : DynamicAccess<Dynamic> {
		var map : DynamicAccess<Dynamic> = {};
		
		for (i in 0 ... element.elements.length) {
			var element : InputElement = cast element.elements[i];
			
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
							var multipleOutput = [];
							for (j in 0 ... formElement.options.length) {
								var select : OptionElement = cast formElement.options[j];
								if (select.selected) multipleOutput.push(select.value);
							}
							map.set(formElement.name, multipleOutput);
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

	public function toDataClass<T : DataClass>(cls : Class<T>) : T {
		return converter.toDataClass(cls, toAnonymousStructure());
	}

	public function toQueryString() : String {
		var map = toAnonymousStructure();
		var output : Array<String> = [];
		for (name in map.keys()) {
			var value = map.get(name);
			var values : Array<String> = Std.is(value, Array)
				? cast value
				: [Std.string(value)];
			
			for (val in values) {
				output.push(name.urlEncode() + "=" + val.urlEncode());
			}
		}
		return output.join("&");
	}

	public function validate<T : DataClass>(cls : Class<T>) : Array<String> {
		if (!Reflect.hasField(cls, "validate")) throw "No static validate method on class " + cls;
		var data = converter.toAnonymousStructure(cls, toAnonymousStructure());
		return untyped __js__('cls.validate({0})', data);
	}
}
#end
