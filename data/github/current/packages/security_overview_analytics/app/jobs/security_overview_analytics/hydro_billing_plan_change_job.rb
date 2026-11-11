# typed: strict
# frozen_string_literal: true


module SecurityOverviewAnalytics
  class HydroBillingPlanChangeJob < ::HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventRetryHandler

    queue_as :hydro_security_overview_analytics_billing_plan_change

    retry_on_dirty_exit

    sig { returns(Integer) }
    attr_reader :organization_id

    sig { returns(Symbol) }
    attr_reader :billing_plan_action

    class OrganizationNotFoundError < StandardError; end

    resolve_tenant_context do |message|
      org_id = message.dig(:organization, :id)
      ::Organization.find_by(id: org_id)&.business
    end

    sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      organization_payload, action = message.values_at(
        :organization,
        :action
      )
      @organization_id = T.let(organization_payload[:id], Integer)
      @billing_plan_action = T.let(action.to_sym, Symbol)

      GitHub.context.push(organization_id:, action:)
    end

    sig { returns(Organization) }
    memoize def organization
      org = T.let(::Organization.find(@organization_id), T.nilable(::Organization))
      if org.nil?
        raise OrganizationNotFoundError, "Organization with ID #{@organization_id} not found"
      else
        T.let(org, Organization)
      end
    end

    protected

    sig { override.returns(T.untyped) }
    def logging_context
      super.merge({
        "gh.org.id": organization_id,
        "gh.org.billing_plan_action": @billing_plan_action,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center",
        "gh.org.id": organization_id
      })
    end

    sig { void }
    def perform
      if @billing_plan_action == :UPGRADE
        initialization = SecurityOverviewAnalytics::Initialization.for(organization)
        if initialization.any_initialized?
          SecurityOverviewAnalytics::ReconciliationScheduler.run_for(organization)
        else
          initialization.enqueue
        end
        FanoutScheduler.initialize_for(organization)
        FanoutScheduler.reconcile_for(organization)
      else
        GitHub.dogstats.increment("security_overview_analytics.initialization.organization.skipped", tags: all_stats_tags + ["cause:downgrade"])
      end
    end
  end
end
