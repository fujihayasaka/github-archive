# typed: true
# frozen_string_literal: true

require "test_helper"

module AdvancedSecurity
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
          SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
          AdvancedSecurity::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

          assert_hydro_published({
            repository_id: @repo.id,
            feature_enabled: true
          }, schema: "github.security_center.v0.AdvancedSecurityToggled")
        end

        test "publishes disabled event when feature is toggled off" do
          SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(false)
          AdvancedSecurity::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

          assert_hydro_published({
            repository_id: @repo.id,
            feature_enabled: false
          }, schema: "github.security_center.v0.AdvancedSecurityToggled")
        end

        test "does not publish event if repository not found" do
          SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
          GitHub.logger.expects(:info).with(
            "Repository not found.",
            "code.namespace": "AdvancedSecurity::Instrumentation::FeatureToggledPublisher",
            "code.function": :instrument_features_toggled
          )

          AdvancedSecurity::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: -1)
          refute_hydro_messages(schema: "github.security_center.v0.AdvancedSecurityToggled")
        end
      end
    end
  end
end
