# typed: true
# frozen_string_literal: true

module Actions
  module Runners
    class RunTimeToCompleteComponent < ApplicationComponent

      include StatusHelper

      def initialize(time_to_complete:, status:)
        @time_to_complete = time_to_complete
        @status = status
      end

    end
  end
end
