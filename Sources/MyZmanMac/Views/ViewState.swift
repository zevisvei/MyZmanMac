import SwiftUI

/// Same as `@State`, without the SwiftUI macro plugin that only ships with full Xcode
/// (so the app builds with just the Command Line Tools).
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) { storage = State(initialValue: wrappedValue) }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
