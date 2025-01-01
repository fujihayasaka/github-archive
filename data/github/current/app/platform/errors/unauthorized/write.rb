# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Unauthorized::Write < Errors::Execution
      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call(self.class.type, *args, **options)
      end

      def self.type
        "UNAUTHORIZED-WRITE"
      end
    end
  end
end
