# typed: true
# frozen_string_literal: true

require "test_helper"

class InstrumentationHelperTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @user = create :user
    @org = create :organization, admin: @user
    @repo = create(:repository, owner: @org)
  end

  context "secret scanning" do
    test "sends enabled event when feature is on" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

      SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: true
      }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    end

    test "sends disabled event when feature is off" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)

      SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: false
      }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    end
  end

  context "secret scanning push protection" do
    test "sends enabled event when feature is on" do
      SecretScanning::Features::Repo::PushProtection.any_instance.stubs(:enabled?).returns(true)

      SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: true
      }, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
    end

    test "sends disabled event when feature is off" do
      SecretScanning::Features::Repo::PushProtection.any_instance.stubs(:enabled?).returns(false)

      SecretScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: @repo.id)

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: false
      }, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
    end
  end
end
