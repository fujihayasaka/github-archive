# typed: true
# frozen_string_literal: true

module Configurable
  module AllowPrivateRepositoryForking
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "allow_private_repository_forking".freeze

    LEGACY_ENABLED = "true"
    DISABLED = "false"
    EVERYWHERE = "everywhere"
    EVERYWHERE_ALIASES = [EVERYWHERE, LEGACY_ENABLED, "1"].freeze  # includes legacy values

    DISABLED_ALIASES = [DISABLED, false, "0", nil].freeze  # includes legacy values

    ENTERPRISE_ORGANIZATIONS = "enterprise_organizations"
    ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS = "enterprise_organizations_user_accounts"
    SAME_ORGANIZATION_USER_ACCOUNTS = "same_organization_user_accounts"
    USER_ACCOUNTS = "user_accounts"

    SAME_ORGANIZATION = "same_organization"

    PERMITS_ENTERPRISE_ORGANIZATIONS = [ENTERPRISE_ORGANIZATIONS, ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS, EVERYWHERE_ALIASES].flatten.freeze
    PERMITS_SAME_ORGANIZATION = [SAME_ORGANIZATION, PERMITS_ENTERPRISE_ORGANIZATIONS, SAME_ORGANIZATION_USER_ACCOUNTS].flatten.freeze
    PERMITS_USER_ACCOUNTS = [ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS, USER_ACCOUNTS, SAME_ORGANIZATION_USER_ACCOUNTS, EVERYWHERE_ALIASES].flatten.freeze

    VALID_POLICIES = [EVERYWHERE_ALIASES, DISABLED_ALIASES, ENTERPRISE_ORGANIZATIONS, SAME_ORGANIZATION, ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS, SAME_ORGANIZATION_USER_ACCOUNTS, USER_ACCOUNTS].flatten.freeze

    POLICY_OVERRIDES = {
      ENTERPRISE_ORGANIZATIONS => [Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION],
      SAME_ORGANIZATION => [],
      ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS => [Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS, Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION, Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS, Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS],
      USER_ACCOUNTS => [],
      SAME_ORGANIZATION_USER_ACCOUNTS => [Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION, Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS],
      EVERYWHERE => [Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS, Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION, Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS, Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS, Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS]
    }

    def allow_private_repository_forking_disabled_by_inherited_policy?
      !allow_private_repository_forking? && !config.local?(KEY)
    end

    def allow_private_repository_forking(force: false, actor:, policy: nil)
      if supports_enhanced_enterprise_forking_policies?
        return false if policy && !valid_private_forking_policy?(policy)
        return false if policy && is_a?(Organization) && !can_set_allow_private_repository_forking_policy_to?(policy)

        # We are dealing with a business or an enterprise organization and they have the enterprise fork policies feature enabled so we should give
        # them a strong default fork policy if they didn't specify one.
        policy = determine_default_private_repository_forking_policy if policy.nil?
      else
        # If the entity doesn't support enhanced enterprise forking policies, make sure they use the legacy enabled value.
        # This applies to businesses and enterprise orgs without the feature flag as well as regular orgs and repos.
        policy = LEGACY_ENABLED
      end

      changed = config.set!(KEY, policy, actor, force)
      return unless changed

      # if we are updating a policy at the business level, we need to ensure the existing org policies
      # are not less restrictive than the new business policy
      if is_a?(::Business)
        # Queue a job to ensure the orgs have valid policies
        # This is done in a job so we don't timeout in the controller action. If the business has thousands of orgs, this could take a while
        # Queue the job after the setting has changed because the job reads the current setting
        EnsureValidForkingPolicyJob.perform_later(business_id: self.id, actor_id: actor&.id)
      end

      GitHub.dogstats.increment("private_repository_forking.enable")

      payload = allow_private_repository_forking_instrumentation_payload(actor)
      payload[:policy] = policy if supports_enhanced_enterprise_forking_policies?

      GitHub.instrument("private_repository_forking.enable", payload)

      true
    end

    # This should be called in a background job so it won't timeout a controller action if there are thousands of orgs in this enterprise
    def ensure_enterprise_organizations_have_valid_policy_after_update(business_policy, actor)
      T.bind(self, Business)

      organizations.each do |org|
        org_policy = org.get_private_repository_forking_policy

        # if the org has a policy set, we need to see if the policy is allowed for the new enterprise policy
        next if org.can_set_allow_private_repository_forking_policy_to?(org_policy, proposed_business_policy: business_policy)

        # if the org's existing fork policy setting is no longer valid with the new enterprise setting, clear the org setting
        org.clear_private_repository_forking_setting(actor: actor)
      end
    end

    def determine_default_private_repository_forking_policy
      return ENTERPRISE_ORGANIZATIONS if is_a?(Business)

      T.bind(self, T.any(Organization, Repository))

      T.must(business).get_private_repository_forking_policy || ENTERPRISE_ORGANIZATIONS
    end

    def get_private_repository_forking_policy
      policy_value = config.get(KEY)

      # the legacy enabled value `true` is treated as `everywhere` since we didn't have forking restrictions previously
      return EVERYWHERE if supports_enhanced_enterprise_forking_policies? && policy_value == LEGACY_ENABLED

      policy_value
    end

    def allow_private_repository_forking_to_enterprise_organizations?
      if is_a?(Repository)
        return false if fork_group_setting&.deny_external?
      end

      # return true if a fork policy isn't being enforced
      return true unless policy_target.allow_private_repository_forking_policy?

      PERMITS_ENTERPRISE_ORGANIZATIONS.include?(policy_target.get_private_repository_forking_policy)
    end

    def allow_private_repository_forking_to_user_accounts?
      if is_a?(Repository)
        return false if fork_group_setting&.deny_users?
      end

      # return true if a fork policy isn't being enforced
      return true unless policy_target.allow_private_repository_forking_policy?

      PERMITS_USER_ACCOUNTS.include?(policy_target.get_private_repository_forking_policy)
    end

    def allow_private_repository_forking_to_same_organization?
      if is_a?(Repository)
        return false if fork_group_setting&.deny_internal?
      end

      # return true if a fork policy isn't being enforced
      return true unless policy_target.allow_private_repository_forking_policy?

      PERMITS_SAME_ORGANIZATION.include?(policy_target.get_private_repository_forking_policy)
    end

    def allow_private_repository_forking_to_any_location?
      if is_a?(Repository)
        return false if fork_group_setting&.deny_any?
      end

      # return true if a fork policy isn't being enforced
      return true unless policy_target.allow_private_repository_forking_policy?

      EVERYWHERE_ALIASES.include?(policy_target.get_private_repository_forking_policy)
    end

    def valid_private_forking_policy?(policy)
      VALID_POLICIES.include?(policy)
    end

    def block_private_repository_forking(force: true, actor:)
      changed = config.set!(KEY, DISABLED, actor, force)
      return false unless changed

      GitHub.dogstats.increment("private_repository_forking.disable")
      GitHub.instrument(
        "private_repository_forking.disable",
        allow_private_repository_forking_instrumentation_payload(actor))
      true
    end

    def clear_private_repository_forking_setting(actor:)
      changed = config.delete(KEY, actor)
      return unless changed

      GitHub.dogstats.increment("private_repository_forking.clear")
      GitHub.instrument(
        "private_repository_forking.clear",
        allow_private_repository_forking_instrumentation_payload(actor))
    end

    def private_repository_forking_configurable?
      return true unless is_a?(Repository)

      in_organization? && private?
    end

    def allow_private_repository_forking?
      if is_a?(Repository)
        return false if fork_group_setting&.deny_all?
      end

      return true unless private_repository_forking_configurable?

      if is_a?(Repository) && !config.local?(KEY)
        # In the case of a forked repository, we need to check the organization
        # instead of the configuration_owner (User) for cascading
        T.must(organization).allow_private_repository_forking?
      else
        !DISABLED_ALIASES.include?(config.get(KEY))
      end
    end

    # Is the setting enforced by a policy
    #
    # Returns a Boolean, true when the setting is enforced by policy, otherwise
    # false.
    def allow_private_repository_forking_policy?
      # if we have a final value, we have an existing legacy policy.
      return true if config.final?(KEY)

      # For org policies feature, the business won't have a "final" value unless it is a disabled policy.
      # This allows the orgs to override with a more restricive value. We just need to check for the existence of any
      # value at the business or org level.
      return !!config.local?(KEY) if is_a?(Business)

      !!config.local?(KEY) || !!config.inherited?(KEY)
    end

    def can_set_allow_private_repository_forking_policy_to?(policy, proposed_business_policy: nil)
      return false unless supports_enhanced_enterprise_forking_policies?

      # enterprises can set any policy
      return true if is_a?(Business)

      T.bind(self, T.any(Organization, Repository))

      # if the enterprise has a disabled policy, orgs shouldn't be able to set any policy.
      return false if T.must(business).allow_private_repository_forking_policy? && !T.must(business).allow_private_repository_forking?

      # orgs are allowed to disable forking even if the enterprise policy is enabled
      return true if !allow_private_repository_forking?

      business_policy = proposed_business_policy || T.must(business).get_private_repository_forking_policy

      return true unless business_policy

      business_policy == policy || POLICY_OVERRIDES[business_policy]&.include?(policy)
    end

    def get_valid_policy_options_for_private_repository_forking_policy
      return [] unless supports_enhanced_enterprise_forking_policies?
      return POLICY_OVERRIDES.keys if is_a?(Business)

      T.bind(self, T.any(Organization, Repository))

      business_policy = T.must(business).get_private_repository_forking_policy

      return POLICY_OVERRIDES.keys unless business_policy

      POLICY_OVERRIDES[business_policy]
    end

    # Which entities support enhanced enterprise forking policies?
    # This mixin is included for businesses, organizations and repositories. Since only enterprises or enterprise organizations can set an
    # enhanced fork policy (orgs and repos can only enable or disable forks), we only return true if the entity is business or an enterprise org
    def supports_enhanced_enterprise_forking_policies?
      is_a?(Business) || (is_a?(Organization) && business)
    end

    private

    # Who should we check for a private repository forking policy?
    # If this is being called on the repository, we should check the organization if there is one.
    # Otherwise, the default chain is fine.
    def policy_target
      return organization if is_a?(Repository) && in_organization?
      self
    end

    def allow_private_repository_forking_instrumentation_payload(actor)
      payload = { user: actor }

      if self.is_a?(Repository)
        payload[:repo] = self
        payload[:org] = self.organization if self.organization
      elsif self.is_a?(Organization)
        payload[:org] = self
        payload[:business] = self.business if self.business
      elsif self.is_a?(Business)
        payload[:business] = self
      end

      payload
    end
  end
end
