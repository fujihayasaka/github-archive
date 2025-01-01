# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class DateValueDestroy < Base
      extend T::Sig
      include GenericFieldValueDestroyStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueDestroy\Z/
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Date)) }
      def field_class
        MemexProjectColumn::Date
      end
    end
  end
end
