# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class BusinessReconciliationJobTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @biz = create(:business)
        @org = create(:organization, business: @biz)
        @user = create(:user)
        @user2 = create(:user)
        @user_ids = TestEnv.test_with_all_emus? ? ExternalIdentity.by_provider(@biz.external_provider).order(:user_id).pluck(:user_id) : [@user, @user2].map(&:id)
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)

        Initialization.any_instance.stubs(:initialized?).returns(true)

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        end
      end

      context "#perform" do
        test "starts reconciliation for all orgs in a business", skip_enterprise: true do
          @biz.organizations.each do |org|
            OrganizationReconciliationJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
          end

          perform_enqueued_jobs only: [BusinessReconciliationJob] do
            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(business_id: @biz.id, source_event: "stubbed")
            end
          end
        end

        test "starts reconciliation for all EMU in a business", skip_enterprise: true do
          return unless TestEnv.test_with_all_emus?
          @biz.organizations.each do |org|
            OrganizationReconciliationJob.expects(:perform_later).with(has_entries(organization_id: org.id)).never
          end

          @user_ids.each do |user_id|
            OwnerReconciliationJob.expects(:perform_later).with(has_entries(owner_id: user_id)).once
          end

          perform_enqueued_jobs only: [BusinessReconciliationJob] do
            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(
                business_id: @biz.id,
                entity_type: SecurityOverviewAnalytics::Reconciliation::BusinessReconciliationJob::EntityType::User
              )
            end
          end
        end

        test "starts reconciliation for all Orgs and Users in a business", skip_with_all_emus: true, enterprise_only: true do
          @biz.organizations.each do |org|
            OrganizationReconciliationJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
          end

          user_ids = User.where(type: "User").pluck(:id)
          user_ids.each do |user_id|
            OwnerReconciliationJob.expects(:perform_later).with(has_entries(owner_id: user_id)).once
          end

          perform_enqueued_jobs only: [BusinessReconciliationJob] do
            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(
                business_id: @biz.id,
                source_event: "stubbed",
                entity_type: SecurityOverviewAnalytics::Reconciliation::BusinessReconciliationJob::EntityType::Organization
              )
            end

            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(
                business_id: @biz.id,
                source_event: "stubbed",
                entity_type: SecurityOverviewAnalytics::Reconciliation::BusinessReconciliationJob::EntityType::User
              )
            end
          end
        end

        test "does not start reconciliation session if tenant out of scope", skip_with_all_emus: true, skip_enterprise: true do
          org = create(:organization)
          OrganizationReconciliationJob.expects(:perform_later).never
          OwnerReconciliationJob.expects(:perform_later).with(has_entries(owner_id: org.id)).never
          OwnerReconciliationJob.expects(:perform_later).with(has_entries(owner_id: @user.id)).never
          @biz.organizations.each do |org|
            OrganizationReconciliationJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
          end

          perform_enqueued_jobs only: [BusinessReconciliationJob, OwnerReconciliationJob] do
            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(business_id: @biz.id, source_event: "stubbed")
            end

            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(business_id: @biz.id, source_event: "stubbed", entity_type: SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType::User)
            end
          end
        end

        test "does not run owner reconciliation in dotcom if feature flag is enabled and user repos are not available", skip_enterprise: true do
          FeatureFlagHelper.stubs(:check_for_user_repositories?).returns(true)
          AdvancedSecurity::Features::Business::AdvancedSecurity::ForEMUs.any_instance.stubs(:feature_available_for_user_repositories?).returns(false)

          OwnerReconciliationJob.expects(:perform_later).never
          perform_enqueued_jobs only: [BusinessReconciliationJob] do
            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(business_id: @biz.id, source_event: "stubbed", entity_type: SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType::User)
            end
          end
        end

        test "does not run owner reconciliation in GHES if user repos are not available", skip_with_all_emus: true, enterprise_only: true do
          AdvancedSecurity::Features::Business::AdvancedSecurity::ForGHES.any_instance.stubs(:feature_available_for_user_repositories?).returns(false)

          OwnerReconciliationJob.expects(:perform_later).never
          perform_enqueued_jobs only: [BusinessReconciliationJob] do
            assert_nothing_raised do
              BusinessReconciliationJob.perform_later(business_id: @biz.id, source_event: "stubbed", entity_type: SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType::User)
            end
          end
        end

        test "raises if organization is not found" do
          perform_enqueued_jobs only: BusinessReconciliationJob do
            assert_raises ActiveRecord::RecordNotFound do
              BusinessReconciliationJob.perform_later(business_id: @biz.id + 13)
            end
          end
        end

        context "soft-deleted organizations", skip_enterprise: true do
          test "does not start reconciliation for soft-deleted organizations" do
            soft_deleted_org = create :organization, login: "soft-deleted-org", admin: @user, business: @biz

            assert_equal 2, @biz.organizations.count

            perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
              soft_deleted_org.soft_delete!(@user)
            end

            assert_predicate soft_deleted_org, :soft_deleted?
            assert_equal 1, @biz.organizations.count

            @biz.organizations.each do |org|
              OrganizationReconciliationJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
            end

            perform_enqueued_jobs only: [BusinessReconciliationJob] do
              assert_nothing_raised do
                BusinessReconciliationJob.perform_later(business_id: @biz.id, source_event: "stubbed")
              end
            end
          end
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same org" do
          assert_enqueued_jobs 1, only: BusinessReconciliationJob do
            BusinessReconciliationJob.perform_later(business_id: @biz.id)
            BusinessReconciliationJob.perform_later(business_id: @biz.id)
            BusinessReconciliationJob.perform_later(business_id: @biz.id, entity_type: SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType::Organization)
          end
        end
      end
    end
  end
end
