# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IterationValueCreate < Base
      include GenericFieldValueCreateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueCreate\Z/
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Field::Iteration)) }
      def field_class
        MemexProjectColumn::Field::Iteration
      end
    end
  end
end
