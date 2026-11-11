# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class ValidationResult
      def self.from_error(error)
        self.new([error])
      end

      def self.valid
        self.new([])
      end

      attr_reader :errors

      def initialize(errors)
        @errors = errors
      end

      def add_errors(errors)
        @errors |= Array(errors)
      end

      def valid?
        @errors.empty?
      end

      def unique_errors
        errors.uniq { |e| e.unique_key }
      end
    end
  end
end
