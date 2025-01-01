# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class ArgumentError < Errors::Execution
      def initialize(*args, **options)
        super("ARGUMENT_ERROR", *args, **options)
      end
    end
  end
end
