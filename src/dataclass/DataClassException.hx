package dataclass;

class DataClassException {
    public final dataClass : Any;
    public final data : Any;
    public final errors : DataClassErrors;

    public function new(dataClass, data, errors) {
        this.dataClass = dataClass;
        this.data = data;
        this.errors = errors;
    }

    public function toString() {
        final cls : Null<Class<Any>> = Type.getClass(dataClass);
        return (cls == null ? "DataClass" : Type.getClassName(cls)) + " invalid data: " + errors;
    }
}
