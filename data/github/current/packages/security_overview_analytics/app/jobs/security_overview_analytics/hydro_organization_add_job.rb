# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroOrganizationAddJob < ::HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventRetryHandler

    queue_as :hydro_security_overview_analytics_organization_add

    retry_on_dirty_exit

    sig { returns(Integer) }
    attr_reader :organization_id
    # This will allow the job to retry for about 1 hour
    MAX_RETRIES = 8

    class OrganizationNotFoundError < StandardError; end

    T.unsafe(self).retry_on OrganizationNotFoundError, delay: :polynomially_longer, max_retries: MAX_RETRIES do
      # If the organization is nil, we have already retried the job the maximum number of times
      # and we should stop retrying the job.
      GitHub.logger.info(
        "Organization not found after #{MAX_RETRIES} retries, skipping job."
      )
      # Return true to stop reporting exception
      true
    end

    resolve_tenant_context do |message|
      org_id = message.dig(:organization, :id)
      ::Organization.find_by(id: org_id)&.business
    end

    sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      organization = message[:organization]
      @organization_id = T.let(organization[:id], Integer)

      GitHub.context.push(organization_id:)
    end

    sig { void }
    def perform
      initialization = Initialization.for(organization)
      if initialization.any_initialized?
        SecurityOverviewAnalytics::ReconciliationScheduler.run_for(organization)
      else
        initialization.enqueue
      end
      FanoutScheduler.initialize_for(organization)
      FanoutScheduler.reconcile_for(organization)
    end

    sig { returns(Organization) }
    memoize def organization
      org = T.let(::Organization.find_by(id: @organization_id), T.nilable(::Organization))
      if org.nil?
        # Assume we've encountered replication lag since org has just been added. Raise an error to retry the job.
        raise OrganizationNotFoundError, "Organization with ID #{@organization_id} not found, retrying"
      else
        T.let(org, Organization)
      end
    end

    protected

    sig { returns(T.untyped) }
    def logging_context
      super.merge({
        "gh.org.id": organization_id
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center"
      })
    end
  end
end
