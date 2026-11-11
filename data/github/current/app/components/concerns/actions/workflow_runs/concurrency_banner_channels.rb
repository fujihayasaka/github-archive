# typed: true
# frozen_string_literal: true

# rubocop:disable ViewComponent/ComponentsHaveUnitTests -- tested via ConcurrencyBannerComponentTest and JobConcurrencyBannerComponentTest
module Actions
  module WorkflowRuns
    # Shared logic for computing WebSocket channel subscriptions used by
    # concurrency banner components (both workflow-level and job-level).
    #
    # Subscribes to the own suite channel plus the acquired (lock-holding) instance's
    # suite channel for cascading live refresh. Known limitations:
    #
    # 1. Race condition: if the lock holder completes between server render and browser
    #    subscription, the notification is missed and the banner shows stale data until
    #    the next meaningful event (e.g., the waiting job itself starts running).
    #
    # 2. Mid-queue cancellation: if a non-lock-holding item in the queue is cancelled,
    #    the banner won't update because we only subscribe to the lock holder's channel.
    #    The queue count self-corrects on the next lock holder completion.
    module ConcurrencyBannerChannels
      extend T::Helpers
      requires_ancestor { ApplicationComponent }
      abstract!

      sig { abstract.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def blocking_resources; end

      # Returns signed channel strings for each concurrency group's acquired (lock-holding)
      # instance's check_suite, or an empty array if no blocking items or FF is not enabled.
      # Including classes must set @check_suite and @should_update.
      sig { returns(T::Array[String]) }
      def blocking_suite_channels
        return [] unless @should_update
        return [] unless concurrency_queue_ff_enabled?

        suite_ids = blocking_resources
          .select { |item| item[:acquired] }
          .filter_map { |item| item[:check_suite_id] }
          .uniq

        return [] if suite_ids.empty?

        CheckSuite.where(id: suite_ids).filter_map do |suite|
          live_update_view_channel(suite.channel)
        end
      end

      # Returns a space-separated string of signed channel IDs for data-channel.
      # Includes the current suite channel along with any blocking instance channels
      # (one per concurrency group).
      sig { returns(String) }
      def data_channels
        channels = [live_update_view_channel(@check_suite.channel)]
        channels.concat(blocking_suite_channels)
        channels.join(" ")
      end

      # Returns true if the blocking item is a job or reusable workflow from a
      # different workflow run and has a workflow_run_name that should be displayed.
      sig { params(item: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def show_workflow_name?(item)
        concurrency_queue_ff_enabled? &&
          (item[:display_type] == "job" || item[:display_type] == "reusable_workflow") &&
          item[:workflow_run_name].present? &&
          item[:workflow_run_id] != @check_suite.workflow_run&.id
      end

      # Returns the display text for the workflow annotation, e.g. "CI #42".
      # Appends the run number to distinguish runs of the same workflow, unless
      # the run has an explicit name (from `run-name:` YAML), which is already unique.
      sig { params(item: T::Hash[Symbol, T.untyped]).returns(String) }
      def workflow_display_name(item)
        name = item[:workflow_run_name]
        return name.to_s if item[:workflow_run_explicit_name]

        run_number = item[:workflow_run_run_number]
        run_number ? "#{name} ##{run_number}" : name.to_s
      end

      # Returns the display name for a blocking item, appending the run number
      # for "run" display types (e.g. "CI #42") to match the workflow annotation
      # style used for jobs.
      sig { params(item: T::Hash[Symbol, T.untyped]).returns(String) }
      def item_display_name(item)
        return item[:display_name].to_s unless item[:display_type] == "run" && concurrency_queue_ff_enabled?

        workflow_display_name(item)
      end

      private

      sig { abstract.returns(T::Boolean) }
      def concurrency_queue_ff_enabled?; end
    end
  end
end
# rubocop:enable ViewComponent/ComponentsHaveUnitTests
