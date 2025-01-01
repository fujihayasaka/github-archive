# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class NotFound < Errors::Execution
      def initialize(*args, **options)
        super("NOT_FOUND", *args, **options)
      end
    end
  end
end
