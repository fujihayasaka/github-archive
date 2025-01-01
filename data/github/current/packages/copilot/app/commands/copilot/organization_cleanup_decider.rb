# typed: strict
# frozen_string_literal: true

module Copilot
  class OrganizationCleanupDecider
    include GitHub::Memoizer

    sig { params(org: ::Organization, revoke: T.nilable(T::Boolean)).void }
    def initialize(org, revoke = nil)
      @organization = org

      revokable = revoke.nil? ? copilot_org.billable_object.feature_enabled?(:copilot_revokable_access) : revoke

      @is_enterprise_owned = T.let(org.business.present?, T::Boolean)
      @has_revokable_access = T.let(revokable, T::Boolean)
      @has_trial = T.let(copilot_org.on_free_trial? || copilot_org.pending_free_trial?, T::Boolean)
      @billable_owner = T.let(billable_owner, T.any(::Organization, ::Business))
      @billable_result = T.let(billable_result, T::Hash[Symbol, T.any(Symbol, T::Boolean)])
    end

    sig { returns(Symbol) }
    def get_action
      with_logging do
        get_cleanup_action
      end
    end

    private

    sig { returns(Symbol) }
    def get_cleanup_action
      # We need to check billability up front because if the billable owner is trade restricted in any way,
      # their seats must be purged. Any other checks are irrelvant.
      #
      # From a billing perspective, there are only two hard fail states where know we need to clean up seats:
      #
      # 1). They have any trade restrictions
      # 2). They are suspended AND billed through Zuora. We can still bill a suspended owner if they are billed
      #     through other platforms e.g. Azure.
      #
      # Any other value of billable_check[:reason] means we should at least attempt to bill the owner.
      if @billable_result[:reason] == :has_full_trade_restrictions || @billable_result[:reason] == :has_any_trade_restrictions
        return :clean
      end

      cleanup_reason = reason_to_clean

      # For every one of the reason to clean scenarios, we always want to clean if the org is on a trial,
      # or if revokable access is not enabled.
      if cleanup_reason.present?
        return :clean if @has_trial
        return :clean unless @has_revokable_access
      else
        # If the org has an ongoing or pending trial, and no other issues, we can ignore billablity;
        # the org / enterprise is not necessarily guaranteed to be billable depending on trials.
        # Additionally, if Copilot was disabled for some reason during the trial, don't take any action,
        # as this could have been done in error.
        return :none if @has_trial

        # Similarly, we can ignore billability if the org has no Copilot for Business. We will revoke access
        # to either the org or enterprise, and assume that they will continue to be billed til the end of the cycle,
        # or else will correct their issues and get seats reinstated.
        if !copilot_org.has_copilot_for_business?
          return :clean unless @has_revokable_access
          return :revoke_to_org
        end
      end

      # Check if the org is suspended.
      # This state may be recoverable, depending on the billable owner's target billing platform (i.e. zuora or azure).
      # Checking if the org is suspended is also a proxy for enterprise suspension,
      # as any suspended enterprise will also have suspended orgs. Suspension at the enterprise level doesn't matter
      # for the cleaner's operation, but should be noted.
      #
      if cleanup_reason == :suspended
        # Any billable owner that is suspended AND billed through Zuora indicates an unrecoverable state.
        return :clean if copilot_org.billed_via_zuora?
        return :revoke_to_org
      end

      # At this point, we have handled all the potential unrecoverable billable states the owner could be in.
      # Going forward, we only need to check if the org is enterprise-owned to determine
      # which entity (org of enterprise) access will be revoked to.

      # I believe the discrepancy between this and soft deleted is that an org is marked as deleted when
      # it is actively undergoing the deletion process in a background job.
      #
      # By contrast, soft deletion is the liminal state indicating the org shouldn't be available on GitHub
      # and hasn't been cleaned up by the aforementioned job.
      if cleanup_reason == :deleted
        # If the org is deleted, we only want to revoke access if it is enterprise-billed.
        return :revoke_to_enterprise if @is_enterprise_owned
        # All other cases, we clean.
        return :clean
      end

      return :revoke_to_org if reason_to_clean == :disabled

      if cleanup_reason == :archived
        # Archived orgs can't be billed if they are standalone
        return :clean unless @is_enterprise_owned
        return :revoke_to_enterprise
      end

      return :revoke_to_org if cleanup_reason == :spammy || cleanup_reason == :soft_deleted

      :none
    end

    sig { returns(Copilot::Organization) }
    memoize def copilot_org
      Copilot::Organization.new(@organization)
    end

    sig { returns(T.any(::Organization, ::Business)) }
    memoize def billable_owner
      if @is_enterprise_owned
        T.cast(copilot_org.billable_object, ::Business)
      else
        T.cast(copilot_org.billable_object, ::Organization)
      end
    end

    sig { returns(T::Hash[Symbol, T.any(Symbol, T::Boolean)]) }
    memoize def billable_result
      copilot_org.copilot_billable_result
    end

    sig { returns(T.nilable(Symbol)) }
    def reason_to_clean
      if @organization.suspended?
        :suspended
      elsif @organization.deleted?
        :deleted
      elsif @organization.disabled?
        :disabled
      elsif @organization.archived?
        :archived
      elsif @organization.spammy?
        :spammy
      elsif @organization.soft_deleted?
        :soft_deleted
      else
        nil
      end
    end

    sig { params(block: T.proc.returns(Symbol)).returns(Symbol) }
    def with_logging(&block)
      result = yield

      GitHub.logger.info(
        "Organization cleaner eligibility",
        to_h.merge("gh.copilot.org_cleaner.result": result)
      )

      result
    end

    sig { returns(T::Hash[Symbol, T.any(Integer, T::Boolean, GitHub::KV::Result)]) }
    def to_h
      {
        "gh.copilot.org_cleaner.is_enterprise_owned": @is_enterprise_owned,
        "gh.copilot.org_cleaner.has_revokable_access": @has_revokable_access,
        "gh.copilot.org_cleaner.has_trial": @has_trial,
        "gh.copilot.org_cleaner.billable_owner_id": billable_owner.id,
        "gh.copilot.org_cleaner.billable_owner_type": billable_owner.class.name,
        "gh.copilot.org_cleaner.billable": @billable_result[:billable],
        "gh.copilot.org_cleaner.billable.result": @billable_result[:reason],
        "gh.copilot.org_cleaner.reason_to_clean": reason_to_clean
      }
    end
  end
end
