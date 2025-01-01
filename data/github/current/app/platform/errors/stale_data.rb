# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class StaleData < Errors::Execution
      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call("STALE_DATA", *args, **options)
      end
    end
  end
end
