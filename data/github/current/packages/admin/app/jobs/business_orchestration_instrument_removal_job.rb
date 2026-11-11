# typed: strict
# frozen_string_literal: true

class BusinessOrchestrationInstrumentRemovalJob < ApplicationJob
  queue_as :business_orchestration_instrument_removal
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  LOCK_TTL = T.let(5.minutes, Integer)
  GLOBAL_LOCK_KEY = T.let("business_orchestration_instrument_removal", String)

  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  around_perform do |_job, block|
    GitHub::Restraint.new.lock!(GLOBAL_LOCK_KEY, GitHub.business_orchestration_instrument_removal_job_limit, LOCK_TTL) do
      block.call
    end
  end

  sig { params(business_id: Integer, organization_ids: T::Array[Integer], user_ids: T::Array[Integer], business_team_operation: T::Boolean, reason: T.nilable(String), actor: T.nilable(User)).void }
  def perform(business_id:, organization_ids:, user_ids:, business_team_operation:, reason: nil, actor: nil)
    business = Business.find(business_id)
    Organization.where(id: organization_ids).order(:id).each do |org|
      return if kill_switch_enabled?(business)
      User.where(id: user_ids).order(:id).each do |user|
        instrument_options = {
          user: user,
          reason: reason,
          membership_types: ["direct_member"], # Limit to direct members for now. Tracked in https://github.com/github/enterprise-primitives/issues/2433
          actor: actor,
          business_team_operation: business_team_operation
        }

        if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
          instrument_options.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
          # GlobalInstrumenter requires a real user
          instrument_options[:actor] = User.staff_user
        end

        if EnterpriseTeam.enabled_for_organizations?(business: org.business)
          instrument_options[:timestamp_override] = Time.current
        elsif !business_team_operation
          org.instrument(:remove_member, instrument_options)
        end

        options = instrument_options.merge(org: org, action: :remove)
        GlobalInstrumenter.instrument "org.remove_member", options
      end
    end
  end

  private

  sig { params(business: Business).returns(T::Boolean) }
  def kill_switch_enabled?(business)
    business.kill_switch_enabled?("RemoveOrganizationMembersCleanupBusinessOrchestration#instrument_removal", feature_flag: :enterprise_teams_killswitch, log_fields: {
      "gh.business.id": business.id
    })
  end
end
