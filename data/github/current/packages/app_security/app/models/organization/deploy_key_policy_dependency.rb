# typed: strict
# frozen_string_literal: true

module Organization::DeployKeyPolicyDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Organization }

  sig { void }
  def initialize_deploy_key_policy
    # Many test cases rely on the deploy key policy being enabled by default
    # so we should not disable it in test environments.
    return if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    # If a business is associated with the organization,
    # and they have the deploy key policy set to enable, we should inherit it.
    #
    # This is because if the business decides to update the no policy
    # No workflows should break because of the deploy key policy.
    biz = self.associated_business_on_creation || self.business
    if biz && biz.deploy_key_policy_enabled?
      self.configure_deploy_key_policy_on_creation(actor: actor, enable: true)
    else
      self.configure_deploy_key_policy_on_creation(actor: actor, enable: false)
    end
  end
end
