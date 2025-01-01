# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Unprocessable < Errors::Execution
      def initialize(*args, **options)
        super("UNPROCESSABLE", *args, **options)
      end
    end
  end
end
