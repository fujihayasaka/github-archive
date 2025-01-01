# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class SingleSelectValueUpdate < Base
      extend T::Sig
      include GenericFieldValueUpdateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueUpdate\Z/,
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::SingleSelect)) }
      def field_class
        MemexProjectColumn::SingleSelect
      end
    end
  end
end
