# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class Result
    Value = T.type_alias { T.any(T::Boolean, ToggledServiceCollection) }
    Error = T.type_alias { T.any(String, Symbol, Exception) }

    sig { returns(Value) }
    attr_reader :value

    sig { returns(T.nilable(Error)) }
    attr_reader :error

    sig { params(value: Value, error: T.nilable(Error)).void }
    def initialize(value, error = nil)
      @value = value
      @error = error
    end

    sig { returns(T::Boolean) }
    def error?
      !error.nil?
    end

    sig { returns([Value, T.nilable(Error)]) }
    def to_ary
      to_a
    end

    sig { returns([Value, T.nilable(Error)]) }
    def to_a
      [value, error]
    end

    # This will throw a runtime error if the value is not a ToggledServiceCollection
    sig { returns(ToggledServiceCollection) }
    def toggled_services
      T.cast(value, ToggledServiceCollection)
    end

    # This will throw a runtime error if the value is not a ToggledServiceCollection
    sig { params(service: Symbol).returns(T.untyped) }
    def result_for_service(service)
      toggled_services[service]
    end
  end
end
