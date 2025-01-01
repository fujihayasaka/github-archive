# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class TextValueUpdate < Base
      extend T::Sig
      include GenericFieldValueUpdateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueUpdate\Z/,
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Text)) }
      def field_class
        MemexProjectColumn::Text
      end
    end
  end
end
