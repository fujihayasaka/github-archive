# typed: strict
# frozen_string_literal: true

module Configurable
  module OrganizationCodespacesOwnershipSetting
    extend Configurable::Async
    extend T::Helpers

    KEY = "organization_codespaces_ownership_setting"

    USER = "user"
    ORGANIZATION = "organization"

    requires_ancestor { Organization }

    sig { returns(T.nilable(String)) }
    def organization_codespaces_ownership_setting
      # EMU users cannot use organization codespaces, default to ORGANIZATION
      return ORGANIZATION if enterprise_managed_user_enabled?

      # Free orgs can't have org ownership (unless they are in the codespaces_billing_free Feature Flag)
      return USER if self.org_free_plan? && !self.free_codespace_use_enabled?

      # If the enterprise has disabled Codespaces for the org, the org can't take ownership
      return USER if business && Codespaces::BusinessDelegator.new(T.must(business)).codespaces_disabled_for_org?(T.cast(self, Organization))

      setting = self.config.get(KEY)

      return setting if setting.present?

      # Any orgs created before the FF was enabled will not have a setting
      # Should be able to remove this after we backfill all of the orgs that we are putting into
      # the "ALL_USERS_AND_OUTSIDE_COLLABORATORS" & "USER" buckets
      if deprecated_organization_codespaces_user_limit == Configurable::OrganizationCodespacesUserLimit::DISABLED
        USER
      else
        ORGANIZATION
      end
    end

    sig { returns(T::Boolean) }
    def has_organization_codespaces_ownership_setting?
      self.config.get(KEY).present?
    end

    sig { params(setting: String, force: T::Boolean, actor: User).returns(T::Boolean) }
    def update_organization_codespaces_ownership_setting(setting, force = false, actor:)
      validate_setting(setting)

      changed = config.set!(KEY, setting, actor, force)

      return false unless changed

      GitHub.dogstats.increment("organization_codespaces_ownership_setting.updated", tags: ["setting:#{setting}"])
      Codespaces::OrgSettingsChangedJob.perform_later(context: self.id, event_type: Codespaces::Events::ORG_CODESPACES_OWNERSHIP_SETTING_UPDATED, actor_id: actor.id)
      instrument :codespaces_ownership_updated, actor: actor, owner_type: setting.capitalize
      changed
    end

    # Method should be called when every new organization is created and the FF is enabled
    sig { returns(T::Boolean) }
    def set_organization_codespaces_ownership_setting_for_new_org
      # Unless org is part of an enterprise, default to user ownership

      setting = (self.business.present? || self.enterprise_managed_user_enabled? || !self.org_free_plan?) ? ORGANIZATION : USER

      update_organization_codespaces_ownership_setting(setting, true, actor: self.owner)
    end

    sig { returns(T::Boolean) }
    def codespaces_ownership_set_to_user?
      organization_codespaces_ownership_setting == USER
    end

    sig { returns(T::Boolean) }
    def codespaces_ownership_set_to_organization?
      organization_codespaces_ownership_setting == ORGANIZATION
    end

    private

    sig { params(setting: String).void }
    def validate_setting(setting)
      raise ArgumentError, "invalid organization codespaces ownership setting" unless [USER, ORGANIZATION].include?(setting)
      raise ArgumentError, "EMU enabled organizations cannot set ownership setting to User" if setting == USER && enterprise_managed_user_enabled?

      if setting == ORGANIZATION && self.org_free_plan? && !enterprise_managed_user_enabled? && !self.free_codespace_use_enabled?
        raise ArgumentError, "Organizations on a free plan cannot set ownership setting to Organization"
      end
    end

  end
end
