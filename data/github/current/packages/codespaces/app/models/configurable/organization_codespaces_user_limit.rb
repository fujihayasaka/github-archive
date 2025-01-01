# typed: true
# frozen_string_literal: true

module Configurable
  module OrganizationCodespacesUserLimit
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }
    requires_ancestor { GitHub::FlipperActor }

    KEY = "organization_codespaces_user_limit"

    DISABLED = "disabled"
    SELECTED_USERS = "selected_users" # TODO: Update this to SELECTED_USERS_AND_TEAMS
    ALL_USERS = "all_users"
    ALL_USERS_AND_OUTSIDE_COLLABORATORS = "all_users_and_outside_collaborators"

    CONFIG_TYPES = [DISABLED, SELECTED_USERS, ALL_USERS, ALL_USERS_AND_OUTSIDE_COLLABORATORS]

    ORG_ENABLED_EVENT_LIMITS = [ALL_USERS, ALL_USERS_AND_OUTSIDE_COLLABORATORS]

    def organization_codespaces_user_limit
      return config.get(KEY) || DISABLED if T.unsafe(self).has_organization_codespaces_ownership_setting? #Every new org after ship should be returning here

      non_ff_setting = deprecated_organization_codespaces_user_limit
      case
      when T.unsafe(self).enterprise_managed_user_enabled?
        access_value = non_ff_setting
        # EMU orgs can't bill to user, so make sure they are moved to the correct ownership setting
        queue_backfill_job(access_value: access_value, ownership_value: Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION)
      when non_ff_setting == DISABLED || (T.unsafe(self).org_free_plan? && !T.unsafe(self).free_codespace_use_enabled?)
        # If their old setting was "Disabled" and they have not modified their ownership setting since the feature was enabled,
        # OR they were on a FREE plan but for some reason their non_ff_setting was not DISABLED
        # We want to "migrate" them to "ALL_USERS_AND_OUTSIDE_COLLABORATORS"
        # New orgs should be created with ownership setting so they will avoid this logic
        # After we ship the FF we should run a transition to backfill so we can remove this conditional.

        access_value = ALL_USERS_AND_OUTSIDE_COLLABORATORS
        queue_backfill_job(access_value: access_value, ownership_value: Configurable::OrganizationCodespacesOwnershipSetting::USER)
      else
        access_value = non_ff_setting
        queue_backfill_job(access_value: access_value, ownership_value: Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION)
      end

      access_value
    end

    def deprecated_organization_codespaces_user_limit
      config.get(KEY) || DISABLED
    end

    def codespaces_access_disabled?
      organization_codespaces_user_limit == DISABLED
    end

    def limits_organizations_codespaces_to_selected_users?
      organization_codespaces_user_limit == SELECTED_USERS
    end

    def limit_organization_codespaces_to_users_and_collaborators?
      organization_codespaces_user_limit == ALL_USERS_AND_OUTSIDE_COLLABORATORS
    end

    def limit_organization_codespaces_to_users?
      organization_codespaces_user_limit == ALL_USERS
    end

    def update_organization_codespaces_user_limit(limit, force = false, actor:)
      raise ArgumentError, "invalid organization codespaces user limit" unless CONFIG_TYPES.include?(limit)

      changed = config.set!(KEY, limit, actor, force)

      return unless changed

      GitHub.dogstats.increment("organization_codespaces_user_limit.updated")
      changed
    end

    # Returns whether the configuration entry has set a policy enforcement
    def has_organization_codespaces_user_limit_policy?
      config.get(KEY) != nil
    end

    def queue_backfill_job(access_value:, ownership_value:)
      if self.feature_enabled?(:codespaces_user_limit_sync_update, memoize: false)
        Codespaces::SetOrganizationCodespacesAccessConfigJob.perform_now(
          organization_id: T.unsafe(self).id,
          access_value: access_value,
          ownership_value: ownership_value
        )
        GitHub.dogstats.increment("organization_codespaces_user_limit_backfill.sync")
      else
        Codespaces::SetOrganizationCodespacesAccessConfigJob.perform_later(
          organization_id: T.unsafe(self).id,
          access_value: access_value,
          ownership_value: ownership_value
        )
      end
    end
  end
end
