# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module NetworkConfigurationPolicy
    extend T::Sig
    extend PolicyFilter

    # Returns the most relevant network configuration from existing policies.
    sig do
      params(
        repository: Repository,
        billable_owner: User,
      ).returns(T.nilable(T::Hash[String, String]))
    end
    def self.get_network_configuration(repository:, billable_owner:)
      return unless billable_owner.organization?
      return unless Codespaces::OrgPolicy.new(user: nil, org: billable_owner).org_admin_can_configure_private_networking?

      params = get_params(
        billable_owner: billable_owner,
        repository: repository
      )

      # There can only be one network configuration policy constraint applicable to a repository
      # Example: [{"id"=>"12334567890", "name"=>"Some Network Name"}, "Repository"]
      params.flatten.first
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION
    end
  end
end
