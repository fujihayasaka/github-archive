# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  # Methods for interacting with the Innersource feature of repository security advisories.
  class Innersource
    # Repo advisories are enabled for public repos by default.
    # For private repos, a repo does not have access to private advisories if:
    # - It or it's org is enrolled in the deprecation feature flag and either:
    #   - The environment is Proxima or GHES
    #   - The environment is dotcom and the repo is private
    # TODO: We will need to exempt GHES from feature flags before enterprise release.
    sig { params(repo: T.nilable(Repository)).returns(T::Boolean) }
    def self.private_advisory_exempt_repo?(repo:)
      return false if repo.nil?
      return false unless FeatureFlag.vexi.enabled?(:private_advisories_disabled, default: false) ||
        repo.feature_flag_enabled?(:private_advisories_disabled, default: false) ||
        repo.organization&.feature_flag_enabled?(:private_advisories_disabled, default: false)

      GitHub.single_or_multi_tenant_enterprise? || repo.private?
    end

    # A repo is eligible to use innersource advisories IFF:
    #   - Its parent org is authorized to use innersource advisories
    #   - GHAS is enabled for the repo
    #   - The repo is otherwise exempt from private advisories
    #   - Either:
    #     - Environment is dotcom and repo is private
    #     - Environment is Proxima or GHES
    # TODO: We will need to exempt GHES from feature flags before enterprise release.
    sig { params(repo: T.nilable(Repository)).returns(T::Boolean) }
    def self.eligible_repo?(repo:)
      return false if repo.nil?
      return false if repo.organization.nil?
      return false if repo.archived?

      org_authorized?(org: repo.organization) &&
        repo.advanced_security_enabled? &&
        private_advisory_exempt_repo?(repo:)
    end

    # A repo is authorized to use innersource advisories if:
    #  - It's an eligible repo
    #  - The repo config setting has been enabled
    # Both of these assertions are checked via `innersource_advisories_enabled?`
    sig { params(repo: T.nilable(Repository)).returns(T::Boolean) }
    def self.repo_authorized?(repo:)
      return false if repo.nil?

      repo.innersource_advisories_enabled?
    end

    # Is this org authorized on its own, or through a parent business for inner source advisories?
    sig { params(org: T.nilable(Organization)).returns(T::Boolean) }
    def self.org_authorized?(org:)
      return false if org.nil?
      (FeatureFlag.vexi.enabled?(:innersource_advisories, org, default: false) && code_security_entitled?(org_or_business: org)) ||
        business_authorized?(business: org.business)
    end

    # Is this business authorized for inner source advisories?
    sig { params(business: T.nilable(Business)).returns(T::Boolean) }
    def self.business_authorized?(business:)
      return false if business.nil?
      FeatureFlag.vexi.enabled?(:innersource_advisories, business, default: false) && code_security_entitled?(org_or_business: business)
    end

    # Does this org or business hold a GHAS Code Security entitlement?
    #
    # Innersource advisories require GHAS Code Security on a Team or Enterprise plan. This is
    # satisfied on the resolved billable entity by any of:
    #   - the unbundled Code Security split SKU, via `code_security_purchased_for_entity?`
    #   - the bundled GHAS SKU (GHAS_VOLUME or GHAS_METERED), via `ghas_sku_purchased_for_entity?`
    #   - an active Code Security trial on the billable entity
    #
    # The entity-level (`*_for_entity?`) helpers are deliberate here: `advanced_security_billable_entity`
    # already resolves the org→business hand-off to the entity that holds the SKU, so we check that
    # entity directly. The higher-level `code_security_purchased?` re-resolves via `billable_owner`,
    # which differs from `advanced_security_billable_entity` for orgs that delegate billing but
    # carry their own split-SKU config — mixing the two would mis-deny that case.
    #
    # Free/Pro orgs are denied implicitly: they cannot purchase any GHAS SKU.
    # Customers with only the Secret Protection split SKU are denied: neither helper matches.
    sig { params(org_or_business: T.nilable(T.any(Organization, Business))).returns(T::Boolean) }
    def self.code_security_entitled?(org_or_business:)
      return false if org_or_business.nil?
      billable = org_or_business.advanced_security_billable_entity
      return false if billable.nil?

      billable.code_security_purchased_for_entity? ||
        billable.ghas_sku_purchased_for_entity? ||
        ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable).enabled?
    end
  end
end
