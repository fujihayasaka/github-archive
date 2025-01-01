# typed: true
# frozen_string_literal: true

module Actions
  module Inputs
    class NumberInputComponent < ApplicationComponent
      attr_reader :id

      def initialize(input:, id:)
        @input = input
        @id = id
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

      def label
        @input[:description].blank? ? name : @input[:description]
      end
    end
  end
end
