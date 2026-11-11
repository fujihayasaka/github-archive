# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module PortPrivacyPolicy
    extend PolicyFilter

    PORT_PRIVACY_SETTINGS = {
      PRIVATE: "private",
      ORG: "org",
      PUBLIC: "public",
    }

    DEFAULT_ORGANIZATION_PRIVACY_SETTINGS = [
      PORT_PRIVACY_SETTINGS[:PRIVATE],
      PORT_PRIVACY_SETTINGS[:ORG],
      PORT_PRIVACY_SETTINGS[:PUBLIC],
    ]

    DEFAULT_USER_PRIVACY_SETTINGS = [
      PORT_PRIVACY_SETTINGS[:PRIVATE],
      PORT_PRIVACY_SETTINGS[:PUBLIC],
    ]

    # Returns port privacy settings filtered by the port privacy policy associated with the repository organization.
    # If there is no policy or constraints, all possible port privacy settings are returned.
    def self.get_allowed_port_privacy_settings(repository:, billable_owner:)
      allowlists = repository ? get_allowlists(billable_owner: billable_owner, repository: repository) : []

      if allowlists.empty?
        return (!billable_owner.nil? && billable_owner.organization?) ? DEFAULT_ORGANIZATION_PRIVACY_SETTINGS : DEFAULT_USER_PRIVACY_SETTINGS
      end

      # Get intersection of allowed port privacy settings.
      allowed_port_privacy_settings = allowlists.reduce(:&)

      # Always return at least the private option.
      allowed_port_privacy_settings.append(PORT_PRIVACY_SETTINGS[:PRIVATE])
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS
    end
  end
end
