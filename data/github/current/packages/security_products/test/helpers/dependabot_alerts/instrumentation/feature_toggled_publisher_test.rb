# typed: true
# frozen_string_literal: true

require "test_helper"

module DependabotAlerts
  module Instrumentation
    class FeatureToggledPublisherTest < GitHub::TestCase
      include HydroMessageJobTestHelpers
      include HydroTestHelpers

      fixtures do
        @user = create(:user)
        @org = create(:organization, admin: @user)
        @repo = create(:repository, owner: @org)
      end

      context "#instrument_features_toggled" do
        test "publishes enabled event when feature is toggled on" do
          SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
          DependabotAlerts::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

          assert_hydro_published({
            action: "enable",
            repository_id: @repo.id,
            owner_id: @org.id
          }, schema: "github.security_alerts.v1.RepositoryVulnerabilityAlertsAnalyticsEvent")
        end

        test "publishes disabled event when feature is toggled off" do
          SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(false)
          DependabotAlerts::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

          assert_hydro_published({
            action: "disable",
            repository_id: @repo.id,
            owner_id: @org.id
          }, schema: "github.security_alerts.v1.RepositoryVulnerabilityAlertsAnalyticsEvent")
        end

        test "does not publish event if repository not found" do
          GitHub.logger.expects(:info).with(
            "Repository not found.",
            "code.namespace": "DependabotAlerts::Instrumentation::FeatureToggledPublisher",
            "code.function": :instrument_features_toggled
          )

          DependabotAlerts::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: -1)
          refute_hydro_messages(schema: "github.security_alerts.v1.RepositoryVulnerabilityAlertsAnalyticsEvent")
        end
      end
    end
  end
end
