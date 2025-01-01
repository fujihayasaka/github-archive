# typed: true
# frozen_string_literal: true

module Actions
  module Inputs
    class DropdownInputComponent < ApplicationComponent
      attr_reader :id

      def initialize(input:, id:, options: nil)
        @input = input
        @id = id
        @options = options
      end

      private

      def name
        @input[:name]
      end

      def value
        @input[:default]
      end

      def required?
        @input[:required]
      end

      def options
        @options || @input[:options] || []
      end

      def label
        @input[:description].blank? ? name : @input[:description]
      end
    end
  end
end
