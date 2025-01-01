# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  module Instrumentation
    class FeatureToggledPublisherTest < GitHub::TestCase
      include HydroMessageJobTestHelpers
      include HydroTestHelpers

      fixtures do
        @user = create(:user)
        @org = create(:organization, admin: @user)
        @repo = create(:repository, :minimal, owner: @org)
      end

      context "#instrument_features_toggled" do
        test "publishes enabled event when feature is toggled on" do
          Repository.any_instance.stubs(:security_feature_configured?).returns(true)
          CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

          assert_hydro_published(
            {
              repository_id: @repo.id,
              feature_enabled: true
            },
            schema: "code_scanning.v0.CodeScanningFeatureToggled",
            topic: "github.code_scanning.v0.CodeScanningFeatureToggled"
          )
        end

        test "publishes disabled event when feature is toggled off" do
          Repository.any_instance.stubs(:security_feature_configured?).returns(false)
          CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

          assert_hydro_published(
            {
              repository_id: @repo.id,
              feature_enabled: false
            },
            schema: "code_scanning.v0.CodeScanningFeatureToggled",
            topic: "github.code_scanning.v0.CodeScanningFeatureToggled"
          )
        end

        test "does not publish event if repository not found" do
          GitHub.logger.expects(:info).with(
            "Repository not found.",
            "code.namespace": "CodeScanning::Instrumentation::FeatureToggledPublisher",
            "code.function": :instrument_features_toggled
          )

          CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: -1)
          refute_hydro_messages(schema: "code_scanning.v0.CodeScanningFeatureToggled")
        end

        test "does not publish event if turboscan returns nil" do
          Repository.any_instance.stubs(:security_feature_configured?).returns(nil)
          GitHub.logger.expects(:info).with(
            "No enablement status returned from Turboscan",
            "code.namespace": "CodeScanning::Instrumentation::FeatureToggledPublisher",
            "code.function": :instrument_features_toggled
          )

          CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)
          refute_hydro_messages(schema: "code_scanning.v0.CodeScanningFeatureToggled")
        end
      end
    end
  end
end
