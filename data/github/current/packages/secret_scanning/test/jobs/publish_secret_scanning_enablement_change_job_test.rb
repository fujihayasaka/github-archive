# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecretScanning::Jobs
  class PublishSecretScanningEnablementChangeJobTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper
    include DogstatsTestHelpers
    include HydroTestHelpers
    include JobTestHelper

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @owner = create(:user)
      @business = create(:global_business)
      @org = create(:organization, business: @business, name: "test-org")
      @org2 = create(:organization, business: @business, name: "test-org-2")
      @owner = @org.admin
      4.times do
        create(:repository, owner: @org)
      end
      4.times do
        create(:repository, owner: @org2)
      end
      4.times do
        create(:repository, owner: @owner, force_user_owned: true)
      end
      unless GitHub.enterprise?
        @emu = create(:emu)
        @emu_biz = @emu.enterprise_managed_business
        @emu_org = create(:organization, business: @emu_biz, name: "test-org-emu")
        4.times do
          create(:repository, owner: @emu_org)
        end
        4.times do
          create(:repository, owner: @emu, force_user_owned: true)
        end
      end
    end

    setup do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    end

    context "#perform" do
      test "retries on error" do
        assert_retry_on_dirty_exit(job: PublishSecretScanningEnablementChangeJob, args: [enablement_level: :organization, actor_id: @owner.id, business: nil, organization: @org])
      end

      test "calls the service to publish an event for each repo in the org" do
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(4)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :organization, actor_id: @owner.id, business: nil, organization: @org)
      end

      test "calls the service for each repo in each org in the business, without user-owned repos", skip_with_all_emus: true do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false) if GitHub.enterprise?

        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(8)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end

      test "calls the service for each repo in each org in the business, plus for each user-owned repo" do
        skip unless GitHub.enterprise? || TestEnv.test_with_all_emus?

        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(12)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end

      test "enables validity checks for each repo in the org if the org has enabled them" do
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:enable_with_org_or_enterprise?).returns(true)
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:enable_with_org_or_enterprise?).returns(true)
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Repo::ValidityChecks.any_instance.expects(:enable).times(4)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :organization, actor_id: @owner.id, business: nil, organization: @org)
      end

      test "enables validity checks for each repo in each org in the business if the business has enabled them" do
        SecretScanning::Features::Org::ValidityChecks.any_instance.stubs(:enable_with_org_or_enterprise?).returns(true)
        SecretScanning::Features::Repo::ValidityChecks.any_instance.stubs(:enable_with_org_or_enterprise?).returns(true)
        SecretScanning::Features::Business::ValidityChecks.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Features::Org::ValidityChecks.any_instance.expects(:enable).times(2)
        SecretScanning::Features::Repo::ValidityChecks.any_instance.expects(:enable).times(8)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end
    end

    context "on Dotcom", skip_enterprise: true do
      test "ignores non-EMU user-owned repos" do
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(@org.repositories.size + @org2.repositories.size)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end

      test "calls the service for each EMU-owned repo in an enterprise-managed-business" do
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(@emu_org.repositories.size + @emu.repositories.size)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @emu.id, business: @emu_biz, organization: nil)
      end

      test "ignores EMU-owned repos if GHAS is not purchased" do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(@emu_org.repositories.size)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @emu.id, business: @emu_biz, organization: nil)
      end
    end

    context "on GHES", enterprise_only: true do
      test "includes user-owned repos if the feature flag is enabled" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(@org.repositories.size + @org2.repositories.size + @owner.repositories.size)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end

      test "ignores user-owned repos if GHAS is not purchased" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(@org.repositories.size + @org2.repositories.size)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end

      test "ignores user-owned repos if the feature flag is disabled" do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)
        SecretScanning::Instrumentation::EnablementChangePublisher
          .expects(:publish_enablement_change_event_for_repository)
          .times(@org.repositories.size + @org2.repositories.size)
          .returns(nil)
        PublishSecretScanningEnablementChangeJob.perform_now(enablement_level: :business, actor_id: @owner.id, business: @business, organization: nil)
      end
    end
  end
end
