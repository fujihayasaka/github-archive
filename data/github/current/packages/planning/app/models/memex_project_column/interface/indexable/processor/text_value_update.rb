# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class TextValueUpdate < Base
      include GenericFieldValueUpdateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueUpdate\Z/,
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Field::Text)) }
      def field_class
        MemexProjectColumn::Field::Text
      end
    end
  end
end
