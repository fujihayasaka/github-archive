# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    class ResetJob < ApplicationJob
      include GitHub::Memoizer

      queue_as :security_overview_analytics_tenant_initialization
      locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
      retry_on_dirty_exit
      retry_on_recoverable_exceptions
      retry_on Freno::Error, wait: :polynomially_longer

      sig do
        params(
          business_ids: T::Array[Integer],
          organization_ids: T::Array[Integer],
          private_beta: T::Boolean, # If true, `business_ids` and `organization_ids` are ignored in favor of the IDs in the private beta feature flag.
          type: T.nilable(String),
          initialization_only: T::Boolean, # If true, data will not be deleted and KV lock will not be cleared before re-initialization.
        ).void
      end
      def perform(business_ids: [], organization_ids: [], private_beta: false, type: nil, initialization_only: false)
        type = Initialization::Type.deserialize(type) if type

        if private_beta
          business_ids = private_beta_business_ids
          organization_ids = private_beta_org_ids
        end

        tags = all_stats_tags + [
          "private_beta:#{private_beta}",
          "initialization_type:#{type&.serialize || "all"}",
        ]

        GitHub.dogstats.distribution_time("security_overview_analytics.reset_job.dist", tags:) do
          if initialization_only
            enqueue_business_initialization_jobs(business_ids:, type:) if business_ids.any?
            enqueue_organization_initialization_jobs(organization_ids:, type:) if organization_ids.any?
          else
            DeletionHelper.delete_all_for_businesses(business_ids:, type:) if business_ids.any?
            DeletionHelper.delete_all_for_organizations(organization_ids:, type:) if organization_ids.any?

            # Use write connection to avoid replication delay after KV changes.
            ActiveRecord::Base.connected_to(role: :writing) do
              enqueue_business_initialization_jobs(business_ids:, type:) if business_ids.any?
              enqueue_organization_initialization_jobs(organization_ids:, type:) if organization_ids.any?
            end
          end
        end

        GitHub.dogstats.increment("security_overview_analytics.reset_job.performed", tags:)
      end

      sig { params(business_ids: T::Array[Integer], type: T.nilable(Initialization::Type)).void }
      def enqueue_business_initialization_jobs(business_ids:, type: nil)
        business_ids.each do |id|
          ::SecurityOverviewAnalytics::Initialization::BusinessJob.perform_later(business_id: id, type: type&.serialize)
        end
        GitHub.logger.info(
          "Business initialization enqueued.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.businesses_initialized": business_ids,
        )
      end

      sig { params(organization_ids: T::Array[Integer], type: T.nilable(Initialization::Type)).void }
      def enqueue_organization_initialization_jobs(organization_ids:, type: nil)
        organization_ids.each do |id|
          ::SecurityOverviewAnalytics::Initialization::OrganizationJob.perform_later(organization_id: id, type: type&.serialize)
        end
        GitHub.logger.info(
          "Organization initialization enqueued.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.organizations_initialized": organization_ids,
        )
      end

      sig { returns(T::Array[Integer]) }
      memoize def private_beta_business_ids
        GitHub
          .flipper[:security_center_private_beta]
          .actors_value
          .to_a
          .select { |v| v.include?("Business") }
          .map { |v| Integer(v.split(":")[1]) }
          .sort
      end

      sig { returns(T::Array[Integer]) }
      memoize def private_beta_org_ids
        GitHub
          .flipper[:security_center_private_beta]
          .actors_value
          .to_a
          .select { |v| v.include?("Organization") }
          .map { |v| Integer(v.split(":")[1]) }
          .sort
      end

      protected

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.security_overview_analytics.job.business_ids": business_ids.present? ? "#{business_ids.first}..#{business_ids.last}" : [],
          "gh.security_overview_analytics.job.organization_ids": organization_ids.present? ? "#{organization_ids.first}..#{organization_ids.last}" : [],
          "gh.security_overview_analytics.job.private_beta": arguments.dig(0, :private_beta),
          "gh.security_overview_analytics.job.type": arguments.dig(0, :type),
          "gh.security_overview_analytics.job.initialization_only": arguments.dig(0, :initialization_only),
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({ app: "github-security-center" })
      end

      sig { returns(T::Array[Integer]) }
      memoize def organization_ids
        arguments.dig(0, :organization_ids) || []
      end

      sig { returns(T::Array[Integer]) }
      memoize def business_ids
        arguments.dig(0, :business_ids) || []
      end
    end
  end
end
