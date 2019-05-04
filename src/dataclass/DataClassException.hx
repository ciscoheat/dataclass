package dataclass;

class DataClassException {
    public final dataClass : Any;
    public final errors : DataClassErrors;

    public function new(dataClass, errors) {
        this.dataClass = dataClass;
        this.errors = errors;
    }
}
