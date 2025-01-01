# typed: true
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module SecuritySettings
      class DependenciesComponent < ApplicationComponent
        extend T::Sig

        TEST_SELECTOR = "security-center-dependencies-settings"

        sig { params(enablement_data: Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data).void }
        def initialize(enablement_data)
          @enablement_data = enablement_data
        end

        def setting_disabled?(feature)
          case feature
          when :dependency_graph
            @enablement_data.dependency_graph_blocked_by_policy ||
            @enablement_data.dependency_graph_always_enabled_for_public_repos ||
            !@enablement_data.dependency_graph_toggle_visible
          when :dependabot_alerts
            @enablement_data.dependabot_alerts_blocked_by_policy ||
            !@enablement_data.dependabot_alerts_toggle_visible
          when :dependabot_security_updates
            @enablement_data.dependabot_security_updates_blocked_by_policy ||
            # TODO: the toggle visible logic for security updates does not involve checking for
            # GHES environment, unlike the other two features. This is currently 1:1 with the
            # logic in the old settings page so for now it's okay, but we should verify this.
            !@enablement_data.dependabot_security_updates_toggle_visible
          end
        end

        def feature_enabled_at_instance_level?(feature)
          case feature
          when :dependency_graph
            GitHub.dependency_graph_enabled?
          when :dependabot_alerts
            SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
          when :dependabot_security_updates
            SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
          end
        end

        def blocked_message
          if features_blocked_by_policy.any?
            "Modifying #{features_blocked_by_policy.to_sentence} has been blocked by an enterprise policy. "
          end
        end

        def feature_description(feature)
          case feature
          when :dependency_graph
            if @enablement_data.dependency_graph_always_enabled_for_public_repos
              "Dependency graph is always enabled for public repositories."
            elsif !@enablement_data.dependency_graph_toggle_visible
              safe_join([
                "Contact your GitHub administrators to update ",
                ActionController::Base.helpers.link_to(
                  "this feature",
                  "https://docs.github.com/enterprise-server@3.2/code-security/supply-chain-security/understanding-your-software-supply-chain/about-the-dependency-graph"
                ),
                "."]
              )
            else
              "Understand your dependencies."
            end
          when :dependabot_alerts
            if !@enablement_data.dependabot_alerts_toggle_visible
              safe_join([
                "Contact your GitHub administrators to update ",
                ActionController::Base.helpers.link_to(
                  "this feature",
                  "https://docs.github.com/code-security/dependabot/dependabot-alerts/about-dependabot-alerts"
                ),
                "."]
              )
            else
              "Receive alerts for vulnerabilities that affect your dependencies."
            end
          when :dependabot_security_updates
            if !@enablement_data.dependabot_security_updates_toggle_visible
              safe_join([
                "Contact your GitHub administrators to update ",
                ActionController::Base.helpers.link_to(
                  "this feature",
                  "https://docs.github.com/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates"
                ),
                "."]
              )
            else
              "Automatically open pull requests to resolve Dependabot alerts."
            end
          end
        end

        private

        memoize def features_blocked_by_policy
          features_blocked = []
          features_blocked << "dependency graph" if @enablement_data.dependency_graph_blocked_by_policy
          features_blocked << "Dependabot alerts" if @enablement_data.dependabot_alerts_blocked_by_policy
          features_blocked << "Dependabot security updates" if @enablement_data.dependabot_security_updates_blocked_by_policy
          features_blocked
        end
      end
    end
  end
end
