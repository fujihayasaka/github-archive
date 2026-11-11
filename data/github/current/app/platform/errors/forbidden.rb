# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Forbidden < Errors::Execution
      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call("FORBIDDEN", *args, **options)
      end
    end
  end
end
