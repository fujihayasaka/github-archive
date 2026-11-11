# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class IterationValueDestroy < Base
      include GenericFieldValueDestroyStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueDestroy\Z/
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Field::Iteration)) }
      def field_class
        MemexProjectColumn::Field::Iteration
      end
    end
  end
end
