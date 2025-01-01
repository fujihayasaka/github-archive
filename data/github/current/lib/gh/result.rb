# typed: strict
# frozen_string_literal: true

module GH
  class Result
    extend T::Helpers
    extend T::Generic

    Value = type_member

    abstract!

    sig { abstract.returns(T::Boolean) }
    def ok?; end

    sig { abstract.returns(T.nilable(Value)) }
    def ok; end

    sig { abstract.returns(T.nilable(Error[Value])) }
    def error; end

    sig do
      abstract
        .type_parameters(:U)
        .params(block: T.proc.params(value: Value).returns(GH::Result[T.type_parameter(:U)]))
        .returns(GH::Result[T.type_parameter(:U)])
    end
    def and_then(&block); end

    sig do
      abstract
        .type_parameters(:U)
        .params(block: T.proc.params(value: Error[Value]).returns(Result[T.type_parameter(:U)]))
        .returns(GH::Result[T.type_parameter(:U)])
    end
    def or_else(&block); end

    sig { abstract.returns(Value) }
    def unwrap!; end

    class Ok < Result
      extend T::Generic

      Value = type_member

      sig { params(value: Value).void }
      def initialize(value)
        @value = value
      end

      sig { returns(Value) }
      attr_reader :value

      sig { override.returns(T::Boolean) }
      def ok?
        true
      end

      sig { override.returns(T.nilable(Value)) }
      def ok
        @value
      end

      sig { override.returns(T.nilable(Error[Value])) }
      def error
        nil
      end

      sig do
        override
          .type_parameters(:U)
          .params(block: T.proc.params(value: Value).returns(GH::Result[T.type_parameter(:U)]))
          .returns(GH::Result[T.type_parameter(:U)])
      end
      def and_then(&block)
        block.call(@value)
      end

      sig do
        override
          .type_parameters(:U)
          .params(block: T.proc.params(value: Error[Value]).returns(Result[T.type_parameter(:U)]))
          .returns(GH::Result[T.type_parameter(:U)])
      end
      def or_else(&block)
        T.cast(self, GH::Result::Ok[T.type_parameter(:U)])
      end

      sig { override.returns(Value) }
      def unwrap!
        @value
      end
    end

    class Error < Result
      extend T::Generic

      class ResultError < RuntimeError; end

      Value = type_member

      sig { params(message: T.nilable(String), exception: T.nilable(StandardError)).void }
      def initialize(message = nil, exception = nil)
        @message = message
        @exception = T.let(exception || ResultError.new(message), StandardError)
      end

      sig { returns(T.nilable(String)) }
      attr_reader :message

      sig { override.returns(T::Boolean) }
      def ok?
        false
      end

      sig { override.returns(T.nilable(Value)) }
      def ok
        nil
      end

      sig { override.returns(T.nilable(Error[Value])) }
      def error
        self
      end

      sig { returns(StandardError) }
      def exception
        @exception
      end

      sig do
        override
          .type_parameters(:U)
          .params(block: T.proc.params(value: Value).returns(GH::Result[T.type_parameter(:U)]))
          .returns(GH::Result[T.type_parameter(:U)])
      end
      def and_then(&block)
        T.cast(self, GH::Result::Error[T.type_parameter(:U)])
      end


      sig do
        override
          .type_parameters(:U)
          .params(block: T.proc.params(value: Error[Value]).returns(Result[T.type_parameter(:U)]))
          .returns(GH::Result[T.type_parameter(:U)])
      end
      def or_else(&block)
        block.call(self)
      end

      sig { override.returns(Value) }
      def unwrap!
        raise @exception
      end

      class NotFound < Error
        Value = type_member
        ResultError = Error::ResultError
      end

      class Argument < Error
        Value = type_member
        ResultError = Error::ResultError
      end

      class Forbidden < Error
        Value = type_member
        ResultError = Error::ResultError
      end

      class Gone < Error
        Value = type_member
        ResultError = Error::ResultError
      end

      class AccessDenied < Error
        extend T::Generic

        Value = type_member
        ResultError = Error::ResultError
      end

      class ContentAuthorizationError < Error
        extend T::Generic

        Value = type_member
        ResultError = Error::ResultError

        sig { params(authorization: Value).void }
        def initialize(authorization)
          super("Content Authorization failed")
          @authorization = authorization
        end

        sig { returns(Value) }
        attr_reader :authorization
      end

      class Validation < Error
        extend T::Generic

        Value = type_member
        ResultError = Error::ResultError

        sig { params(model: ActiveModel::Validations, message: T.nilable(String)).void }
        def initialize(model, message: nil)
          super(message)
          @model = model
        end

        sig { returns(ActiveModel::Validations) }
        attr_reader :model
      end

      class Unprocessable < Error
        Value = type_member
        ResultError = Error::ResultError

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

        Value = type_member
        ResultError = Error::ResultError
      end

      class ServiceRateLimited < Error
        extend T::Generic

        Value = type_member
      end

      class ServiceUnavailable < Error
        extend T::Generic

        Value = type_member
      end

      class ServiceUnreachable < Error
        extend T::Generic

        Value = type_member
      end

      # This error corresponds to GitHub::Prioritizable::Context::LockedForRebalance
      class LockedForRebalance < Error
        extend T::Generic

        Value = type_member
        ResultError = Error::ResultError
      end

      class NotSaved < Error
        extend T::Generic

        Value = type_member
        ResultError = Error::ResultError
      end
    end
  end
end
