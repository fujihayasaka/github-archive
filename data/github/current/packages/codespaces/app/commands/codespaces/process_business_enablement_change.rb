
# typed: strict
# frozen_string_literal: true

module Codespaces
  class ProcessBusinessEnablementChange < Command
    extend T::Sig
    class InvalidEnablementError < StandardError; end
    sig { returns(::Business) }
    attr_reader :business

    sig { returns(::User) }
    attr_reader :actor

    sig { returns(String) }
    attr_reader :enablement

    sig { returns(String) }
    attr_reader :orgs_to_update

    sig { params(business: ::Business, actor: ::User, enablement: String, orgs_to_update: String).void }
    def initialize(business:, actor:, enablement:, orgs_to_update: "")
      @business = business
      @actor = actor
      @enablement = enablement
      @orgs_to_update = orgs_to_update
    end

    sig { override.void }
    def perform
      return unless business.present?

      case enablement
      when Codespaces::EnablementPolicyInputPresenter::DISABLED
        process_all_disable
      when Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES
        process_all_enable
      when Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES
        process_selected_enable
      else
        raise InvalidEnablementError.new("Invalid enablement value: #{enablement}")
      end
    end

    private

    sig { returns(Codespaces::BusinessDelegator) }
    memoize def business_delegator
      Codespaces::BusinessDelegator.new(business)
    end

    sig { params(orgs: ActiveRecord::Relation, event_type: String).void }
    def queue_jobs_for_orgs(orgs, event_type)
      instrument_label = event_type == Codespaces::Events::ORG_REPO_OWNED_CODESPACES_ENABLED ? "enabled" : "disabled"

      orgs.find_in_batches do |org_batch|
        org_names = org_batch.map do |org|
          Codespaces::OrgSettingsChangedJob.perform_later(
            context: org.id,
            event_type: event_type,
            actor_id: actor.id,
          )
          org.name
        end
        if enablement == Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES
          GitHub.instrument("codespaces.business_enablement_updated", instrumentation_context(instrument_label, org_names))
        end
      end
    end

    sig { void }
    def process_all_disable
      previously_enabled_orgs = business_delegator.codespaces_policy_enabled_organizations
      business_delegator.disable_codespaces!
      queue_jobs_for_orgs(previously_enabled_orgs, Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED)
      GitHub.instrument("codespaces.business_enablement_updated", instrumentation_context("all-orgs-disabled", []))
    end

    sig { void }
    def process_all_enable
      previously_disabled_orgs = business.organizations.where.not(id: business_delegator.codespaces_policy_enabled_organizations)
      business_delegator.enable_codespaces_for_all_organizations!
      queue_jobs_for_orgs(previously_disabled_orgs, Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED)
      GitHub.instrument("codespaces.business_enablement_updated", instrumentation_context("all-orgs-enabled", []))
    end

    sig { void }
    def process_selected_enable
      previously_enabled_orgs = business_delegator.codespaces_policy_enabled_organizations
      previously_disabled_orgs = business.organizations.where.not(id: business_delegator.codespaces_policy_enabled_organizations)

      save_org_enablement_changes
      business_delegator = BusinessDelegator.new(business) #Reload the business delegator to get the latest changes

      currently_enabled_orgs = business_delegator.codespaces_policy_enabled_organizations
      currently_disabled_orgs = business.organizations.where.not(id: business_delegator.codespaces_policy_enabled_organizations)

      #Get the diff between the orgs that were previously enabled/disabled and the orgs that are currently enabled/disabled
      orgs_to_disable = currently_disabled_orgs.where.not(id: previously_disabled_orgs)
      orgs_to_enable = currently_enabled_orgs.where.not(id: previously_enabled_orgs)

      queue_jobs_for_orgs(orgs_to_disable, Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED)
      queue_jobs_for_orgs(orgs_to_enable, Codespaces::Events::ORG_REPO_OWNED_CODESPACES_ENABLED)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def save_org_enablement_changes
      orgs_ids = orgs_to_update.present? ? JSON.parse(orgs_to_update.presence).group_by { |_k, v| v } : nil
      if orgs_ids.present?
        business_delegator.enable_codespaces_for_selected_organizations!(orgs_ids["enable"].map(&:first)) if orgs_ids["enable"].present?
        business_delegator.disable_codespaces_for_selected_organizations!(orgs_ids["disable"].map(&:first)) if orgs_ids["disable"].present?
      else
        business_delegator.enable_codespaces_for_selected_organizations!([])
      end
    end

    sig { params(enablement_label: String, org_names: T::Array[String]).returns(T::Hash[T.untyped, T.untyped]) }
    def instrumentation_context(enablement_label, org_names)
      {
        actor_id: actor.id,
        business: business,
        enablement: enablement_label,
      }.tap do |h|
        h[:organization_names] = org_names.sort if org_names.any?
      end
    end
  end
end
