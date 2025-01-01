# typed: strict
# frozen_string_literal: true

# TODO: when writing logic to update this policy, we should be sure that changes to dotcom chat
# update this policy. if dotcom chat is no policy, so is this policy, if dotcom chat is enabled, this policy
# should be set to disabled (if changing from disabled/no policy)
# if disabling dotcom chat, disable this policy

module Copilot
  module Policies
    class DotcomBetaFeatures
      class << self
        include Copilot::Policy

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
          "beta_features_github_chat"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot in GitHub.com preview features"
        end

        # actually a tos url
        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#previews"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          if entity.sorbet_class == ::User
            user = T.cast(entity, Copilot::User)
            return false if user.has_limited_access?
          end

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          # if inherited value is nil, that means the policy is not configured
          # so we default to disabled
          inherited_policy || "disabled"
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :copilot_beta_features_opt_in_setting
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :copilot_beta_features_opt_in_setting
        end

        private

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
            enabled: :COPILOT_BETA_FEATURES_OPT_IN_ENABLED,
            disabled: :COPILOT_BETA_FEATURES_OPT_IN_DISABLED,
            no_policy: :COPILOT_BETA_FEATURES_OPT_IN_NO_POLICY,
            unconfigured: :COPILOT_BETA_FEATURES_OPT_IN_DISABLED,
            unknown: :COPILOT_BETA_FEATURES_OPT_IN_UNKNOWN
          }
        end

        sig do override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_DISABLED,
            invalid: MonolithTwirp::Copilot::Users::V1::CopilotBetaFeaturesOptIn::COPILOT_BETA_FEATURES_OPT_IN_INVALID
          }
        end
      end
    end
  end
end
