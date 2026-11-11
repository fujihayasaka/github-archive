# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class AutomaticCodeReview
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::User::Mutable

        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "automatic_code_review"
        end

        sig { override.returns(String) }
        def display_name
          "Automatic Copilot code review"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/using-github-copilot/code-review/configuring-automatic-code-review-by-copilot"
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Copilot will automatically review your pull requests.",
            PolicyDescriptionChunk.new(text: "Learn more about configuring automatic code review.", href: documentation_url)
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          copilot_user.has_cfi_access? && super
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          required_cfi_plan = if entity.feature_flag_enabled?(:ccr_access_free, default: false)
            Copilot::Plans::CFI::Free
          else
            Copilot::Plans::CFI::Pro
          end

          experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: required_cfi_plan) do
            if entity.sorbet_class == ::User
              user = T.cast(entity, Copilot::User)
              return true if user.has_trial_access?
              return false if user.has_limited_access? && !entity.feature_flag_enabled?(:ccr_access_free, default: false)
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
          return value(user) if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(T::Boolean) }
        def skip_organization_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_business_instrumentation?
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
            enabled: :AUTOMATIC_CODE_REVIEW_ENABLED,
            disabled: :AUTOMATIC_CODE_REVIEW_DISABLED,
            no_policy: :AUTOMATIC_CODE_REVIEW_NO_POLICY,
            unconfigured: :AUTOMATIC_CODE_REVIEW_UNCONFIGURED,
            unknown: :AUTOMATIC_CODE_REVIEW_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::AutomaticCodeReview::AUTOMATIC_CODE_REVIEW_INVALID
          }
        end
      end
    end
  end
end
