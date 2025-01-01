# typed: true
# frozen_string_literal: true

module GH
  module RecordTransformer
    extend T::Helpers
    extend T::Generic

    ValueType = type_member

    interface!

    sig { abstract.params(records: T.untyped).returns(T::Array[ValueType]) }
    def from_records(records); end
  end
end
