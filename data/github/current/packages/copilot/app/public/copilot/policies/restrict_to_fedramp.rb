# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class RestrictToFedramp
      # rubocop:disable Style/ClassMethodsDefinitions
      class << self
        include Copilot::PolicyInterface
        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "restrict_to_fedramp"
        end

        sig { override.returns(String) }
        def display_name
          "Restrict Copilot to FedRAMP Models"
        end

        sig { override.returns(String) }
        def documentation_url
          "" #this needs to be filled in later
        end

        sig { returns(String) }
        def description
          "If enabled, Copilot will limit functionality to only use FedRAMP approved models. Please be aware that this may disable access to other Copilot features."
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [description]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [description]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [description]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_restrict_to_fedramp_policy, default: false)

          experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: nil) do
            # Users cannot configure the policy, but can see if their seat provider has turned it on
            if entity.sorbet_class == ::User
              user = T.cast(entity, Copilot::User)
              return user.has_cb_access? || user.has_ce_access?
            end
            true
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "unconfigured" unless available_for?(user)

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
        end

        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :RESTRICT_TO_FEDRAMP_ENABLED,
            disabled: :RESTRICT_TO_FEDRAMP_DISABLED,
            no_policy: :RESTRICT_TO_FEDRAMP_NO_POLICY,
            unconfigured: :RESTRICT_TO_FEDRAMP_UNCONFIGURED,
            unknown: :RESTRICT_TO_FEDRAMP_UNKNOWN
          }
        end

        sig do
          override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer,
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::RestrictToFedramp::RESTRICT_TO_FEDRAMP_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::RestrictToFedramp::RESTRICT_TO_FEDRAMP_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::RestrictToFedramp::RESTRICT_TO_FEDRAMP_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::RestrictToFedramp::RESTRICT_TO_FEDRAMP_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::RestrictToFedramp::RESTRICT_TO_FEDRAMP_INVALID,
          }
        end
      end
    end
  end
end
