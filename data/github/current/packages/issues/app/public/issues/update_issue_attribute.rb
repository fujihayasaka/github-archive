# typed: strict
# frozen_string_literal: true

module Issues
  class UpdateIssueAttribute
    extend T::Generic
    extend T::Helpers

    Value = type_member

    sealed!
    abstract!

    sig { abstract.params(blk: T.proc.params(v: T.nilable(Value)).void).void }
    def then(&blk); end

    sig do
      abstract
        .type_parameters(:R)
        .params(
          blk: T.proc
            .params(v: T.nilable(Value))
            .returns(T.nilable(T.type_parameter(:R)))
        )
        .returns(UpdateIssueAttribute[T.type_parameter(:R)])
    end
    def map(&blk); end

    class Keep < UpdateIssueAttribute
      extend T::Generic
      Value = type_member

      sig { override.params(blk: T.proc.params(v: T.nilable(Value)).void).void }
      def then(&blk); end

      sig do
        override
        .type_parameters(:R)
        .params(
          blk: T.proc.params(arg0: T.nilable(Value)).returns(T.nilable(T.type_parameter(:R)))
        )
        .returns(Issues::UpdateIssueAttribute[T.type_parameter(:R)])
      end
      def map(&blk)
        T.cast(self, UpdateIssueAttribute[T.type_parameter(:R)])
      end
    end

    class Unset < UpdateIssueAttribute
      extend T::Generic
      Value = type_member

      sig { override.params(blk: T.proc.params(v: T.nilable(Value)).void).void }
      def then(&blk)
        blk.call(nil)
      end

      sig do
        override
        .type_parameters(:R)
        .params(
          blk: T.proc.params(arg0: T.nilable(Value)).returns(T.nilable(T.type_parameter(:R)))
        )
        .returns(Issues::UpdateIssueAttribute[T.type_parameter(:R)])
      end
      def map(&blk)
        T.cast(self, UpdateIssueAttribute[T.type_parameter(:R)])
      end
    end

    class Set < UpdateIssueAttribute
      extend T::Generic
      Value = type_member

      sig { params(value: Value).void }
      def initialize(value)
        @value = value
      end

      sig { override.params(blk: T.proc.params(v: T.nilable(Value)).void).void }
      def then(&blk)
        blk.call(@value)
      end

      sig do
        override
        .type_parameters(:R)
        .params(
          blk: T.proc.params(arg0: T.nilable(Value)).returns(T.nilable(T.type_parameter(:R)))
        )
        .returns(Issues::UpdateIssueAttribute[T.type_parameter(:R)])
      end
      def map(&blk)
        Issues::UpdateIssueAttribute::Set.new(blk.call(@value))
      end
    end
  end
end
