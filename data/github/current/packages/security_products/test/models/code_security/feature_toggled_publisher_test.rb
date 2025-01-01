# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeSecurity
  class FeatureToggledPublisherTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include SecretScanning::Features::FeatureFlagHelper

    setup do
      @user = create :user
      @org = create :organization, admin: @user
      @repo = create(:repository, owner: @org)
    end

    context "code security" do
      test "queues a refresh rule state on enable job" do
        SecurityProduct::CodeSecurity.new(@repo).on_enable(actor: @user, options: {})

        assert_hydro_published({
          repository_id: @repo.id,
          feature_enabled: true
        }, schema: "github.code_security.v1.CodeSecurityFeatureToggled")
        assert_enqueued_jobs 1, only: RefreshRuleStateOnGhasEnablementChangeJob
        assert_enqueued_with(job: RefreshRuleStateOnGhasEnablementChangeJob, args: [{ repository: @repo, ghas_enabled: true }])
      end

      test "queues a refresh rule state on disable job" do
        @repo.config.enable(SecurityProduct::CodeSecurity::USER_ENABLED_KEY, @user)
        SecurityProduct::CodeSecurity.new(@repo).on_disable(actor: @user, options: {})

        assert_hydro_published({
          repository_id: @repo.id,
          feature_enabled: false
        }, schema: "github.code_security.v1.CodeSecurityFeatureToggled")
        assert_enqueued_jobs 1, only: RefreshRuleStateOnGhasEnablementChangeJob
        assert_enqueued_with(job: RefreshRuleStateOnGhasEnablementChangeJob, args: [{ repository: @repo, ghas_enabled: false }])
      end
    end
  end
end
