# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class TextValueCreate < Base
      extend T::Sig
      include GenericFieldValueCreateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueCreate\Z/,
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Text)) }
      def field_class
        MemexProjectColumn::Text
      end
    end
  end
end
