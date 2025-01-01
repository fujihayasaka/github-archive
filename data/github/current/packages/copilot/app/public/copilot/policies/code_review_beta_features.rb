# typed: strict
# frozen_string_literal: true

# Similar to dotcom beta features, we will need to make sure we properly update this
# on code review policy change

module Copilot
  module Policies
    class CodeReviewBetaFeatures
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
          "code_review_beta_features"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot code review preview features"
        end

        # actually tos url
        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#previews"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_code_review_policy, default: false)

          if entity.sorbet_class == ::User
            user = T.cast(entity, Copilot::User)
            return true if user.has_trial_access?
            return false if user.has_limited_access? && !user.feature_flag_enabled?(:ccr_access_free, default: false)
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

          # cfi users and those with trial access should always have this on
          return "enabled" if user.has_cfi_access? || user.has_trial_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          if !inherited_policy.nil?
            inherited_policy
          else
            # if the inherited value is nil, first try and do the ea fallback.
            # if there is no fallback, the policy is unconfigured
            user.business_copilot_provider_ea_user_fallback_policy(:code_review_beta_features) || "unconfigured"
          end
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
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
            enabled: :CODE_REVIEW_BETA_FEATURES_ENABLED,
            disabled: :CODE_REVIEW_BETA_FEATURES_DISABLED,
            no_policy: :CODE_REVIEW_BETA_FEATURES_NO_POLICY,
            unconfigured: :CODE_REVIEW_BETA_FEATURES_UNCONFIGURED,
            unknown: :CODE_REVIEW_BETA_FEATURES_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::CodeReviewBetaFeatures::CODE_REVIEW_BETA_FEATURES_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CodeReviewBetaFeatures::CODE_REVIEW_BETA_FEATURES_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CodeReviewBetaFeatures::CODE_REVIEW_BETA_FEATURES_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CodeReviewBetaFeatures::CODE_REVIEW_BETA_FEATURES_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CodeReviewBetaFeatures::CODE_REVIEW_BETA_FEATURES_INVALID
          }
        end
      end
    end
  end
end
