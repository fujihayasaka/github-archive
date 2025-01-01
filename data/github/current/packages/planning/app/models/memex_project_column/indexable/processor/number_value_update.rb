# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class NumberValueUpdate < Base
      extend T::Sig
      include GenericFieldValueUpdateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueUpdate\Z/,
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Number)) }
      def field_class
        MemexProjectColumn::Number
      end
    end
  end
end
