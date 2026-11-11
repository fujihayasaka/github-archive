# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class DateValueDestroy < Base
      include GenericFieldValueDestroyStrategy

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v0\.MemexProjectColumnValueDestroy\Z/
        ]
      end

      sig { override.returns(T.class_of(MemexProjectColumn::Field::Date)) }
      def field_class
        MemexProjectColumn::Field::Date
      end
    end
  end
end
