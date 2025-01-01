# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class SingleSelectValueDestroy < Base
      extend T::Sig
      extend T::Helpers
      include GenericFieldValueDestroyStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueDestroy\Z/
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::SingleSelect)) }
      def field_class
        MemexProjectColumn::SingleSelect
      end
    end
  end
end
