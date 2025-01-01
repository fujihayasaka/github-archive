# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class ArgumentLimit < Errors::Execution
      def initialize(*args, **options)
        super("ARGUMENT_LIMIT", *args, **options)
      end
    end
  end
end
