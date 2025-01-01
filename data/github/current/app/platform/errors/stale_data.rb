# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class StaleData < Errors::Execution
      def initialize(*args, **options)
        super("STALE_DATA", *args, **options)
      end
    end
  end
end
