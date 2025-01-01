# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class IterationValueCreate < Base
      extend T::Sig
      include GenericFieldValueCreateStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueCreate\Z/
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Iteration)) }
      def field_class
        MemexProjectColumn::Iteration
      end
    end
  end
end
