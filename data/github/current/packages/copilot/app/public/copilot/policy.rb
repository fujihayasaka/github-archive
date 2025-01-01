# typed: strict
# frozen_string_literal: true

module Copilot
  module Policy
    include Kernel

    extend T::Helpers

    interface!

    # name of the policy, should match the name of enum in the config model
    sig { abstract.returns(String) }
    def config_name; end

    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(String) }
    def value(entity); end

    # user-friendly name of the policy, used in UI and documentation
    sig { abstract.returns(String) }
    def display_name; end

    # url to the documentation of the policy, used in UI and documentation
    sig { abstract.returns(String) }
    def documentation_url; end

    # base getters, we define four main states:
    # - enabled
    # - disabled
    # - no_policy: defer setting the policy to the entity below (business only)
    # - unconfigured: no policy set at all

    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def enabled?(entity); end

    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def disabled?(entity); end

    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def no_policy?(entity); end

    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def unconfigured?(entity); end

    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def configured?(entity); end

    # is the policy is available for the given actor
    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def available_for?(entity); end

    # is the policy is available for the given actor in public preview
    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def preview?(entity); end

    # is the policy editable by the given entity
    sig { abstract.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
    def editable_by?(entity); end

    # computes the whether the policy is enabled or not given inheritance and other rules
    # if you are computing the effective value for more than one policy, you should pass
    # in the all_policies param so that we don't recompute all policies many times
    sig { abstract.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
    def effective_value(user, all_policies = nil); end

    # TODO: when migrating each kind of entity over, remove these from the class and instead cast to the mutable types
    # when needed. This will allow us to prevent accidental mutations of policies that are not mutable.
    sig { abstract.params(user: Copilot::User, value: String).void }
    def update_user(user, value); end

    # used to determine if the orgs policy is inherited from its business
    # needed since we propagate the business policy to the orgs
    sig { abstract.params(org: Copilot::Organization).returns(T::Boolean) }
    def org_policy_inherited?(org); end

    # values to check for the policy state, override these if you are using non-standard values
    # in the configuration records for your policy
    sig do abstract.returns({
        enabled: String,
        disabled: String,
        no_policy: String,
        unconfigured: String,
      })
    end
    def config_values; end


    sig { abstract.params(config: Copilot::Configuration, value: String).void }
    def update!(config, value); end
  end
end
