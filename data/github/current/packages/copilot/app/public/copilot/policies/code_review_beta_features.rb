# typed: strict
# frozen_string_literal: true

# Similar to dotcom beta features, we will need to make sure we properly update this
# on code review policy change

module Copilot
  module Policies
    class CodeReviewBetaFeatures
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

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

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, members licensed through organizations within this enterprise can access previews of new Copilot code review features. Use of previews is subject to",
            PolicyDescriptionChunk.new(text: "GitHub's pre-release terms", href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members licensed in this organization can use previews of new Copilot code review features. Use of previews is subject to",
            PolicyDescriptionChunk.new(text: "GitHub's pre-release terms", href: documentation_url)
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          super && Copilot::Policies::CodeReview.enabled?(copilot_business)
        end

        sig { override.params(entity: T.any(Copilot::Types::CopilotEntity, Copilot::Public::User)).returns(T::Boolean) }
        def available_for?(entity)
          experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro) do
            case entity
            when Copilot::User, Copilot::Public::User
              return true if entity.has_trial_access?
              return false if entity.has_limited_access?
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
          return "disabled" unless available_for?(user)

          # cfi users and those with trial access should always have this on
          return "enabled" if user.has_cfi_access? || user.has_trial_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "disabled"
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:disabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:disabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:disabled]
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
