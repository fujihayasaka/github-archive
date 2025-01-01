# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Contains constants that hold instrumentation strings
# and methods to intrument hydro events

module Codespaces
  module Events
    # Emitted after an admin disables codespaces for the organization (billing)
    #
    # The event payload will include:
    #   organization_id - the organization id
    ORG_CODESPACES_DISABLED = "codespaces.disabled"

    # Emitted after an admin enables codespaces for all users in the organization (billing)
    #
    # The event payload will include:
    #   organization_id - the organization id
    ORG_CODESPACES_ENABLED = "codespaces.enabled"

    # Emitted after an admin changes codespace ownership setting in the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    ORG_CODESPACES_OWNERSHIP_SETTING_UPDATED = "codespaces.org_ownership_setting_updated"

    # Emitted after an admin disables codespaces for the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    ORG_REPO_OWNED_CODESPACES_DISABLED = "codespaces.org_repos_disabled"

    # Emitted after an admin enables codespaces for the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    ORG_REPO_OWNED_CODESPACES_ENABLED = "codespaces.org_repos_enabled"

    # Emitted after an admin enables codespaces for a user in the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    #   user_id - the enabled user
    ORG_CODESPACES_ENABLED_USER = "codespaces.enabled_user"

    # Emitted after an admin disables codespaces for a user in the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    #   user_id - the disabled user
    ORG_CODESPACES_DISABLED_USER = "codespaces.disabled_user"

    # Emitted after an admin enables codespaces for a user in the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    #   team_id - the enabled team
    ORG_CODESPACES_ENABLED_TEAM = "codespaces.enabled_team"

    # Emitted after an admin disables codespaces for a team in the organization
    #
    # The event payload will include:
    #   organization_id - the organization id
    #   team_id - the disabled team
    ORG_CODESPACES_DISABLED_TEAM = "codespaces.disabled_team"

    # Emitted during processing of billing messages when a codespace cannot be billed
    #
    # The event payload will include:
    #   codespace_id - the codespace id
    INACCESSIBLE_CODESPACE = "codespaces.inaccessible_codespace"

    # Emitted during processing of billing messages as a proxy for codespace usage
    BILLING_COMPUTE_ANALYTICS = "codespaces.compute_analytics"
    BILLING_STORAGE_ANALYTICS = "codespaces.storage_analytics"

    # Emitted when a codespace is started
    CODESPACE_START = "codespaces.start"

    # Emitted when a codespace is suspended
    CODESPACE_SUSPEND = "codespaces.suspend"

    # Emitted when a codespace's repository is changed
    CODESPACE_REPOSITORY_CHANGED = "codespaces.repository_changed"

    # Emitted when a user interacts with a codespace in various ways
    CODESPACE_INTERACTION = "codespaces.interaction"
    # Used for metadata field forked_from_onboarding_repo on CODESPACE_INTERACTION event
    ONBOARDING_REPO_OWNER = "github"
    ONBOARDING_REPO_NAME = "haikus-for-codespaces"
    ONBOARDING_REPO_NWO = "#{ONBOARDING_REPO_OWNER}/#{ONBOARDING_REPO_NAME}"

    # Emitted when we calculate the trust tier for a user
    CODESPACES_TRUST_TIER_CALCULATED = "codespaces.trust_tier_calculated"

    def self.start(codespace)
      GlobalInstrumenter.instrument(CODESPACE_START,
        codespace: codespace,
        actor: codespace.owner
      )
    end

    def self.suspend(codespace)
      GlobalInstrumenter.instrument(CODESPACE_SUSPEND,
        codespace: codespace,
        actor: codespace.owner
      )
    end

    def self.interaction(codespace:, type:, source: nil, client: nil, client_usage: nil)
      GlobalInstrumenter.instrument(CODESPACE_INTERACTION, {
        codespace: codespace,
        actor: codespace.owner,
        type: type,
        source: source,
        client: client,
        forked_from_onboarding_repo: forked_from_onboarding_repo?(codespace.repository),
        attempted_from_prebuild: codespace.environment_data&.attempted_from_prebuild,
        client_usage: client_usage
      })
    end

    def self.forked_from_onboarding_repo?(repo)
      return false unless repo&.fork?
      repo.parent.name_with_owner == ONBOARDING_REPO_NWO  # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    def self.client_usage_is_valid?(client_usage)
      return false unless client_usage
      valid = begin
        Hydro::Schemas::Github::Codespaces::V0::Entities::ClientUsage.new(client_usage)
        true
      rescue Google::Protobuf::TypeError
        false
      rescue Hydro::Protobuf::InvalidValueError
        false
      end
      valid
    end

    def self.trust_tier_calculated(actor, calculated_trust_tier, tier_deciding_accounts)
      GlobalInstrumenter.instrument(CODESPACES_TRUST_TIER_CALCULATED,
        actor: actor,
        calculated_trust_tier: calculated_trust_tier,
        tier_deciding_accounts: tier_deciding_accounts
      )
    end
  end
end
