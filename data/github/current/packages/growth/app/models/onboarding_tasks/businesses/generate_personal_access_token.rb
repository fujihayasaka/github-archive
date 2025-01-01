# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class GeneratePersonalAccessToken < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Generate SCIM token"
      end

      sig { override.returns(String) }
      def task_link
        completed? ? settings_user_tokens_url(only_path: true) : new_settings_user_token_path(description: "SCIM provisioning", scopes: "admin:enterprise", default_expires_at: "none", show_onboarding_guide_tip: true)
      end

      sig { returns(String) }
      def task_link_text
        completed? ? "Manage tokens" : title
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        T.must(user).oauth_accesses.personal_tokens.any?
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(String) }
      def icon_path
        "modules/site/icons/info.svg"
      end

      sig { returns(String) }
      def help_link
        "#{GitHub.help_url}/admin/managing-iam/provisioning-user-accounts-with-scim/configuring-scim-provisioning-for-users#creating-a-personal-access-token"
      end

      sig { returns(String) }
      def help_link_text
        "Learn more about personal access tokens"
      end
    end
  end
end
