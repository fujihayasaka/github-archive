# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class NotFound < Errors::Execution
      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call("NOT_FOUND", *args, **options)
      end
    end
  end
end
