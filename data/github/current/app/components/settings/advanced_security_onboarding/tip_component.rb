# typed: strict
# frozen_string_literal: true

module Settings
  module AdvancedSecurityOnboarding
    class TipComponent < ApplicationComponent
      extend T::Sig

      class TipBannerAttributes < T::Struct
        const :task_class, T.class_of(OnboardingTasks::AdvancedSecurity::Base)
        const :title, String
        const :body, T.any(String, T.class_of(ApplicationComponent))
      end

      ATTRIBUTES = T.let({
        "advanced_security" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::EnableAdvancedSecurity,
          title: "Enable Advanced Security",
          body: "Click ‘Enable all’ to allow advanced security features to be turned on your organization.",
        ),
        "code_scanning" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::EnableCodeScanning,
          title: "Enable Code Scanning",
          body: "Click ‘Enable all’ to prevent and fix vulnerabilities as you write code.",
        ),
        "secret_scanning" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::EnableSecretScanning,
          title: "Enable Secret Scanning",
          body: "Click ‘Enable all’ to detect and prevent secret leaks across your organization's repositories.",
        ),
        "scanning_new_repos" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::EnableScanningNewRepos,
          title: " Automatically enable features on new repositories",
          body: "Select the checkboxes to ensure new repositories are protected by default with advanced security and secret scanning enablement.",
        ),
        "security_managers" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::AssignSecurityManagers,
          title: "Assign security manager roles",
          body: Settings::AdvancedSecurityOnboarding::SecurityManagerTipComponent,
        ),
        "security_overview" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::SecurityOverview,
          title: "Security Overview",
          body: "Uncover insights to help prioritize efforts in your AppSec program and share progress with the various stakeholders across your organization with detailed reporting in a security overview.",
        ),
        "push_protection" => TipBannerAttributes.new(
          task_class: OnboardingTasks::AdvancedSecurity::EnablePushProtection,
          title: "Enable push protection",
          body: "Click 'Enable all' to scan code on commits and receive alerts if a secret is present to prevent leaks from occurring before push. Quickly remove the secret with the exact location of the secret, along with suggestions for remediation.",
        ),
      }.freeze, T::Hash[String, TipBannerAttributes])

      sig { returns(T.nilable(TipBannerAttributes)) }
      attr_reader :tip_banner_attributes

      sig { returns(T.nilable(::Organization)) }
      attr_reader :organization

      sig { returns(T.nilable(String)) }
      attr_reader :visible_for_tip

      sig { returns(T.nilable(String)) }
      attr_reader :tip

      sig { returns(T::Boolean) }
      attr_reader :with_separator

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig do params(
        tip: T.nilable(String),
        organization: T.nilable(::Organization),
        visible_for_tip: T.nilable(String),
        with_separator: T::Boolean,
        system_arguments: T.untyped,
      ).void
      end
      def initialize(tip:, organization:, visible_for_tip: nil, with_separator: false, **system_arguments)
        @tip_banner_attributes = T.let(tip && ATTRIBUTES[tip], T.nilable(TipBannerAttributes))
        @organization = organization
        @tip = tip
        @visible_for_tip = visible_for_tip
        @with_separator = with_separator
        @system_arguments = system_arguments
      end

      sig { returns(T::Boolean) }
      def render?
        return false if visible_for_tip.present? && visible_for_tip != tip
        return false unless @organization
        return false unless business = @organization.business
        return false if GitHub.enterprise?
        return false if @organization.enterprise_managed_user_enabled?

        tip_banner_attributes.present?
      end
    end
  end
end
