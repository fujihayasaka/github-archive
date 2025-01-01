# typed: true
# frozen_string_literal: true

module Actions
  module Inputs
    class BooleanInputComponent < ApplicationComponent
      attr_reader :id

      def initialize(input:, id:)
        @input = input
        @id = id
      end

      private

      def name
        @input[:name]
      end

      def checked?
        @input[:default] == "true"
      end

      def label
        @input[:description].blank? ? name : @input[:description]
      end

      def required?
        @input[:required]
      end
    end
  end
end
