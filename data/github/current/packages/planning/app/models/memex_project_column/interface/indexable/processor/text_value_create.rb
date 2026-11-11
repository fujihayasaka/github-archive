# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class TextValueCreate < Base
      include GenericFieldValueCreateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueCreate\Z/,
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Field::Text)) }
      def field_class
        MemexProjectColumn::Field::Text
      end
    end
  end
end
