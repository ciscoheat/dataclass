package dataclass;
using StringTools;

/**
 * Date from/to ISO 8601 format.
 */
class DateConverter
{
	public static function toDate(input : String) : Date {
        #if js
        return cast new js.lib.Date(input);
        #else
		final s = input.trim();
		if (s.endsWith('Z')) {
			final isoZulu = ~/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$/;
			inline function d(pos : Int) return Std.parseInt(isoZulu.matched(pos));
			if (isoZulu.match(s)) {
				final hours = Std.int(Math.round(getTimeZone() / 1000 / 60 / 60));
				final minutes = hours * 60 - Std.int(Math.round(getTimeZone() / 1000 / 60));
				@:nullSafety(Off) return new Date(d(1), d(2) - 1, d(3), d(4) + hours, d(5) + minutes, d(6));
			}
		}
		
		return Date.fromString(s);
        #end
	}
	
	public static function toISOString(input : Date) : String {
        #if js
        final d : js.lib.Date = cast input;
        return d.toISOString();
        #else
		final time = DateTools.delta(input, -getTimeZone());
		return DateTools.format(time, "%Y-%m-%dT%H:%M:%SZ");
        #end
	}
	
	// Thanks to https://github.com/HaxeFoundation/haxe/issues/3268#issuecomment-52960338
	static function getTimeZone() {
		var now = Date.now();
		now = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
		return (24. * 3600 * 1000 * Math.round(now.getTime() / 24 / 3600 / 1000) - now.getTime());
	}
}