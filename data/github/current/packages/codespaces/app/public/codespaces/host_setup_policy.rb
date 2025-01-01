# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true
module Codespaces
  module HostSetupPolicy
    extend T::Sig
    extend PolicyFilter

    # Returns host setup config filtered by the host setup policy associated with the repository organization.
    # If there is no policy or constraints, {} is returned
    def self.get_host_setup_config(repository:, billable_owner:)
      # must be in salus beta
      return {} unless billable_owner.in_codespaces_salus_beta?
      # host setup policy must be enabled
      return {} unless billable_owner.feature_enabled?(:codespaces_host_setup_policy)

      params = get_params(
        billable_owner: billable_owner,
        repository: repository
      )

      return {} if params.first.nil? || params.first[0].nil?

      # There can only be one host setup policy constraint applicable to a repository
      # Example: p[{"path"=>"setup.sh", "repo"=>"test", "branch"=>"master"}, "Repository"]
      params.first[0]
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP
    end
  end
end
