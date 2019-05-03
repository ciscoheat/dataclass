package dataclass;

class DataClassException<T> {
    public final dataClass : T;
    public final errors : DataClassErrors;

    public function new(dataClass, errors) {
        this.dataClass = dataClass;
        this.errors = errors;
    }
}
