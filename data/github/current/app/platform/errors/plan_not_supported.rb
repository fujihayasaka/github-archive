# typed: false
# frozen_string_literal: true

module Platform
  module Errors
    class PlanNotSupported < Errors::Execution
      def initialize(*args, **options)
        super("PLAN_NOT_SUPPORTED", *args, **options)
      end
    end
  end
end
