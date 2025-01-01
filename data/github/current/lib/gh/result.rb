# typed: strict
# frozen_string_literal: true

module GH
  class Result
    extend T::Helpers
    extend T::Generic

    Value = type_member { { upper: BasicObject } }

    abstract!

    class Ok < Result
      extend T::Generic

      Value = type_member { { upper: BasicObject } }

      sig { params(value: Value).void }
      def initialize(value)
        @value = value
      end

      sig { returns(Value) }
      attr_reader :value
    end

    class Error < Result
      extend T::Generic

      Value = type_member { { upper: BasicObject } }

      sig { params(message: T.nilable(String)).void }
      def initialize(message = nil)
        @message = message
      end

      sig { returns(T.nilable(String)) }
      attr_reader :message

      class NotFound < Error
        Value = type_member { { upper: BasicObject } }
      end

      class AccessDenied < Error
        extend T::Generic

        Value = type_member { { upper: BasicObject } }
      end

      class Validation < Error
        extend T::Generic

        Value = type_member { { upper: BasicObject } }

        sig { params(model: ActiveModel::Validations, message: T.nilable(String)).void }
        def initialize(model, message: nil)
          super(message)
          @model = model
        end

        sig { returns(ActiveModel::Validations) }
        attr_reader :model
      end

      class Unprocessable < Error
        Value = type_member { { upper: BasicObject } }

        sig { params(items: T::Array[T.anything], message: T.nilable(String)).void }
        def initialize(items, message: nil)
          super(message)
          @items = items
        end

        sig { returns(T::Array[T.anything]) }
        attr_reader :items
      end

      class NotUnique < Error
        extend T::Generic

        Value = type_member { { upper: BasicObject } }
      end
    end
  end
end
