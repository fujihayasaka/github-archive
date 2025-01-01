# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class EnableScanningNewRepos < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Automatically enable advanced security and secret scanning on new repositories"
      end

      sig { override.returns(String) }
      def task_link
        settings_org_security_analysis_path(organization, tip: "scanning_new_repos")
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        organization.advanced_security_enabled_on_new_repos? || SecretScanning::Features::Org::TokenScanning.new(organization).secret_scanning_enabled_for_new_repos?
      end
    end
  end
end
