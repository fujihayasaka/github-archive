# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Validation < Errors::Execution
      def initialize(*args, **options)
        super("VALIDATION", *args, **options)
      end
    end
  end
end
