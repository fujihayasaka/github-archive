# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ArgumentError < Errors::Execution
      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call("ARGUMENT_ERROR", *args, **options)
      end
    end
  end
end
