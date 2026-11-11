# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CodeReview
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::DirectOrgBillingAccess
        include Copilot::Policies::Concerns::Mutable
        include Copilot::Policies::Concerns::Business::Mailable

        include Copilot::Policies::Concerns::Organization::Mailable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "code_review"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot code review"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/enterprise-cloud@latest/copilot/using-github-copilot/code-review/using-copilot-code-review"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, members who are licensed through organizations within this enterprise can use",
            *product_docs_chunks,
            "in any repository they belong to.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members licensed in this organization can use",
            *product_docs_chunks,
            "in any repository they belong to.",
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Use Copilot to",
            PolicyDescriptionChunk.new(text: "review your code", href: Copilot::COPILOT_CODE_REVIEW_DOCUMENTATION),
            "and generate",
            PolicyDescriptionChunk.new(text: "pull request summaries.", href: Copilot::COPILOT_FOR_PRS_DOCUMENTATION)
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          return false unless super

          copilot_business.copilot_organizations.any? do |org|
            org.copilot_enabled? && (org.copilot_plan_enterprise? || org.copilot_plan_business?)
          end
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          return false unless copilot_user.feature_flag_enabled_include_parents?(:copilot_code_review_policy, default: false)

          super
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
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

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          # Bypass the `available_for?` check and check if any of the user's organizations
          # have direct org billing enabled.
          # They won't have their own configuration since they don't have access otherwise.
          return "enabled" if user.feature_flag_enabled?(:ccr_direct_org_billing_user_policy, default: false) &&
            has_access_via_direct_org_billing?(user)

          return "disabled" unless available_for?(user)

          # cfi users and those with trial access should always have this on
          return "enabled" if user.has_cfi_access? || user.has_trial_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        # after update ccr policy, we should make sure we also update the sub policies
        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def post_business_update(copilot_business, value)
          if value == "disabled" || value == "no_policy"
            Copilot::Policies::CodeReviewBetaFeatures.update_business(copilot_business, value)
            Copilot::Policies::CcrDirectOrgBilling.update_business(copilot_business, value)
          elsif value == "enabled"
            # when we re-enable the policy, reset sub policies to default
            # this only has an actual effect when changing from no policy to enabled, and ensures
            # that the value will properly propagate to the org settings
            Copilot::Policies::CodeReviewBetaFeatures.update_business(copilot_business, "disabled")
            Copilot::Policies::CcrDirectOrgBilling.update_business(copilot_business, "disabled")
          end
        end

        sig { override.params(copilot_org: Copilot::Organization, value: String).void }
        def post_organization_update(copilot_org, value)
          # if you disable CCR at the org level, also disable sub policies
          if value == "disabled"
            Copilot::Policies::CodeReviewBetaFeatures.update_org(copilot_org, value)
            Copilot::Policies::CcrDirectOrgBilling.update_org(copilot_org, value)
          end
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotCodeReviewMailer.code_review_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotCodeReviewMailer.code_review_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, admin: ::User).void }
        def send_policy_enabled_email_to_admin(org, admin)
          CopilotCodeReviewMailer.code_review_enabled_for_org_admin(org, admin).deliver_later
        end

        sig { override.params(org: ::Organization, admin: ::User).void }
        def send_policy_no_policy_email_to_admin(org, admin)
          CopilotCodeReviewMailer.code_review_no_policy_for_org_admin(org, admin).deliver_later
        end

        sig { override.params(org: ::Organization, admin: ::User).void }
        def send_policy_disabled_email_to_admin(org, admin)
          CopilotCodeReviewMailer.code_review_disabled_for_org_admin(org, admin).deliver_later
        end

        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def skip_email?(org)
          # Check both the policy feature flag and the email feature flag
          return true unless org.feature_flag_enabled?(:copilot_code_review_policy, default: false)
          !org.feature_flag_enabled?(:copilot_code_review_emails, default: false)
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:unconfigured]
        end

        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def skip_admin_email?(org)
          # Use the same logic as skip_email? for admin emails
          skip_email?(org)
        end

        sig { override.returns(T::Boolean) }
        def send_user_emails_on_propagation?
          # Don't send user emails when enterprise policy propagates to orgs
          # Only send admin emails to reduce email spam
          false
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
            enabled: :CODE_REVIEW_ENABLED,
            disabled: :CODE_REVIEW_DISABLED,
            no_policy: :CODE_REVIEW_NO_POLICY,
            unconfigured: :CODE_REVIEW_UNCONFIGURED,
            unknown: :CODE_REVIEW_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::CodeReview::CODE_REVIEW_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CodeReview::CODE_REVIEW_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CodeReview::CODE_REVIEW_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CodeReview::CODE_REVIEW_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CodeReview::CODE_REVIEW_INVALID
          }
        end

        sig { returns(PolicyDescription) }
        def product_docs_chunks
          [
            PolicyDescriptionChunk.new(text: display_name, href: Copilot::COPILOT_CODE_REVIEW_DOCUMENTATION),
            "and",
            PolicyDescriptionChunk.new(text: "Copilot for pull requests", href: Copilot::COPILOT_FOR_PRS_DOCUMENTATION)
          ]
        end
      end
    end
  end
end
