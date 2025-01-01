# typed: strict
# frozen_string_literal: true

# TODO: This component may never be rendered because security configs are always available to orgs.
# It could be a candidate for code removal.
module SecurityCenter
  module Risk
    class AdvancedSecurityOnboardingTipComponent < ApplicationComponent

      sig { returns(Organization) }
      attr_reader :organization

      sig { returns(T::Boolean) }
      attr_reader :show_tip

      sig { returns(T.untyped) }
      attr_reader :system_arguments

      sig { params(organization: Organization, show_tip: T::Boolean, system_arguments: T.untyped).void }
      def initialize(organization:, show_tip:, **system_arguments)
        @organization = organization
        @show_tip = show_tip
        @system_arguments = system_arguments
      end

      sig { void }
      def before_render
        return if organization.security_configurations_enabled?
        return unless OnboardingTasks::AdvancedSecurity::EnableAdvancedSecurity.new(user: current_user, taskable: organization).completed?
        return unless OnboardingTasks::AdvancedSecurity::EnableSecretScanning.new(user: current_user, taskable: organization).completed?
        return unless OnboardingTasks::AdvancedSecurity::EnableCodeScanning.new(user: current_user, taskable: organization).completed?
        return unless OnboardingTasks::AdvancedSecurity::EnableScanningNewRepos.new(user: current_user, taskable: organization).completed?

        OnboardingTasks::AdvancedSecurity::SecurityOverview.new(user: current_user, taskable: organization).complete
      end
    end
  end
end
