# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class PlanNotSupported < Errors::Execution
      def initialize(*args, **options)
        T.unsafe(Errors::Execution.instance_method(:initialize)).bind(self).call("PLAN_NOT_SUPPORTED", *args, **options)
      end
    end
  end
end
