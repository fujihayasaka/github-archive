# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class BillingItemComponent < ApplicationComponent
      include StatusHelper

      attr_reader :repository, :usage_line_item, :rerun_id, :billing_duration_in_seconds, :runtime_environment, :check_run

      def initialize(
        repository:,
        runtime_environment:,
        billing_duration_in_seconds:,
        usage_line_item: nil,
        check_run: nil,
        rerun_id: nil
      )
        @repository = repository
        @runtime_environment = runtime_environment
        @billing_duration_in_seconds = billing_duration_in_seconds
        @usage_line_item = usage_line_item
        @rerun_id = rerun_id
        @check_run = check_run
      end

      def is_windows?
        platform == :WINDOWS
      end

      def is_macos?
        platform == :MACOS
      end

      private

      memoize def platform
        runtime = @runtime_environment.upcase

        case
        when runtime.include?("MACOS")
          :MACOS
        when runtime.include?("WINDOWS")
          :WINDOWS
        when runtime.include?("UBUNTU")
          :LINUX
        else
          :LINUX
        end
      end
    end
  end
end
