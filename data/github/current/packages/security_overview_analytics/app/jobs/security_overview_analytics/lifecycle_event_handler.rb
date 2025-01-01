# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module LifecycleEventHandler
    extend T::Sig
    extend T::Helpers

    abstract!

    private

    sig { abstract.returns(Time) }
    def event_time; end

    sig { abstract.returns(String) }
    def source_event; end

    sig { returns(T::Boolean) }
    def instrument_repository_updated?
      !Initialization::TenantBaseJob.is_initialization_event?(source_event) &&
      !Reconciliation::OrganizationReconciliationJob.is_reconciliation_event?(source_event)
    end

    module Hydro
      extend T::Sig
      extend T::Helpers
      include LifecycleEventHandler

      abstract!
      requires_ancestor { HydroMessageJob }

      private

      sig { void }
      def instrument_repository_updated
        # skip if not from an incremental source event
        return unless instrument_repository_updated?

        tags = all_stats_tags + ["source_event:#{source_event}"]
        GitHub.dogstats.distribution_timing_since("security_overview_analytics.updated.dist", event_time, tags:)
      end
    end

    module ActiveJob
      extend T::Sig
      extend T::Helpers
      include LifecycleEventHandler

      abstract!
      requires_ancestor { ApplicationJob }

      private

      sig { void }
      def instrument_repository_updated
        # skip if not from an incremental source event
        return unless instrument_repository_updated?

        tags = all_stats_tags + ["source_event:#{source_event}"]
        GitHub.dogstats.distribution_timing_since("security_overview_analytics.updated.dist", event_time, tags:)
      end
    end
  end
end
