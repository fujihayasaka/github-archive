# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    class ResetInitializationJob < ApplicationJob
      extend T::Sig
      include GitHub::Memoizer

      queue_as :security_overview_analytics_business_initialization
      locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      sig do
        params(
          business_ids: T::Array[Integer],
          type: String
        ).void
      end
      def perform(business_ids:, type:)
        type = Initialization::Type.deserialize(type) if type

        tags = all_stats_tags + [
          "initialization_type:#{type.serialize}",
        ]

        GitHub.dogstats.distribution_time("security_overview_analytics.reset_initialization_job.dist", tags:) do
          businesses = Business.where(id: business_ids)
          businesses.each do |business|
            initialization = SecurityOverviewAnalytics::Initialization.for(business)
            with_write do
              initialization.delete_initialization(type:)
            end
          end

        end

        GitHub.dogstats.increment("security_overview_analytics.reset_initialization_job.performed", tags:)
      end

      protected

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.security_overview_analytics.job.business_ids": business_ids.present? ? "#{business_ids.first}..#{business_ids.last}" : [],
          "gh.security_overview_analytics.job.type": arguments.dig(0, :type),
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({ app: "github-security-center" })
      end

      sig { returns(T::Array[Integer]) }
      memoize def business_ids
        arguments.dig(0, :business_ids) || []
      end
    end
  end
end
