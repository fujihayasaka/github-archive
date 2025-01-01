# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class Forbidden < Errors::Execution
      def initialize(*args, **options)
        super("FORBIDDEN", *args, **options)
      end
    end
  end
end
