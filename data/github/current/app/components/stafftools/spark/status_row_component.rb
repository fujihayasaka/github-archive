# typed: true
# frozen_string_literal: true

module Stafftools
  module Spark
    class StatusRowComponent < ApplicationComponent
      # description - String description/label for the status row
      # value - Boolean value indicating success (true) or failure (false)
      # note - Optional String with additional context (default: nil)
      sig { params(description: String, value: T::Boolean, note: T.nilable(String)).void }
      def initialize(description:, value:, note: nil)
        @description = description
        @value = value
        @note = note
      end

      private

      sig { returns(String) }
      attr_reader :description

      sig { returns(T::Boolean) }
      attr_reader :value

      sig { returns(T.nilable(String)) }
      attr_reader :note

      sig { returns(Symbol) }
      def icon
        value ? :"check-circle-fill" : :"x-circle-fill"
      end

      sig { returns(Symbol) }
      def icon_color
        value ? :success : :danger
      end
    end
  end
end
