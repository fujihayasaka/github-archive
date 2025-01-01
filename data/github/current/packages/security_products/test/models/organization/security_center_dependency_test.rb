# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../app/models/security_center/k_v"

class OrganizationSecurityCenterDependencyTest < GitHub::TestCase
  include ::SecurityCenter::TestHelpers

  fixtures do
    @owner = create(:user, name: "org-owner")

    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @business = create(:global_business)

    GitHub.enable_ghe_content_analysis(@owner) if GitHub.enterprise? # enable dependabot

    @org = create(:business_plus_organization, admin: @owner, business: @business).tap do |org|
      # repo with all statuses
      create(:private_repository, owner: org).tap do |repo|
        create(:repository_security_center_config, repository: repo)
        RepositorySecurityCenterStatus.primary_feature_types.each do |feature_type|
          create(:repository_security_center_status, feature_type, :not_enrolled, repository: repo)
          RepositorySecurityCenterStatus.subfeatures_for(feature_type).each do |subfeature_type|
            create(:repository_security_center_status, subfeature_type, :not_enrolled, repository: repo)
          end
        end
      end
    end

    @empty_org = create(:business_plus_organization, admin: @owner, business: @business)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    SecurityCenter::SecurityFeatures.stubs(
      code_scanning_enabled_for_instance?: true,
      secret_scanning_enabled_for_instance?: true,
      dependabot_alerts_enabled_for_instance?: true,
    )

    SecurityCenter::KV.store.del("#{SecurityCenter::OwnerReconciliationJob.name}:#{@org.id}")
  end

  context "#trigger_security_center_reconciliation" do
    context "on org with repositories" do
      test "returns false if org has expected number of config records" do
        refute @org.trigger_security_center_reconciliation
      end

      test "returns false when all feature types aren't visible" do
        SecurityCenter::SecurityFeatures.stubs(:visible_features).with(@org).returns([])
        assert_query_count 7 do
          refute @org.trigger_security_center_reconciliation
        end
      end

      test "returns false when repo is missing dependabot_version_updates status" do
        RepositorySecurityCenterStatus.where(feature_type: :dependabot_version_updates).delete_all
        refute @org.trigger_security_center_reconciliation
      end

      test "returns true and queues job if org has wrong number of config records" do
        T.must(RepositorySecurityCenterConfig.where(owner_id: @org.id).first).destroy
        assert @org.trigger_security_center_reconciliation
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "returns true and queues job if org has wrong number of status records" do
        T.must(RepositorySecurityCenterStatus.where(owner_id: @org.id).first).destroy

        assert_logged_statements([{
          "Body": "Clearing reconciliation lock",
          "code.namespace": "Organization",
          "code.function": "trigger_security_center_reconciliation",
          "gh.org.id": @org.id,
          "gh.org.login": @org.display_login,
        }]) do
          assert @org.trigger_security_center_reconciliation
          assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
        end
      end

      test "queues job" do
        refute @org.trigger_security_center_reconciliation
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "does not queue job within window" do
        @org.trigger_security_center_reconciliation
        Timecop.travel 1.day.from_now do
          @org.trigger_security_center_reconciliation
        end
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "queues job beyond window" do
        @org.trigger_security_center_reconciliation
        Timecop.travel 8.days.from_now do
          @org.trigger_security_center_reconciliation
        end
        assert_enqueued_jobs 2, only: SecurityCenter::OwnerReconciliationJob
      end

      test "does not throw if GitHub.kv raises error" do
        SecurityCenter::KV.store
          .stubs(:set)
          .raises(StandardError.new("test error"))
        Failbot.reports.clear

        @org.trigger_security_center_reconciliation

        assert_equal 1, Failbot.reports.size
        Failbot.reports.each do |report|
          exception_class_dig_args = GitHub.enterprise? ? ["class"] : ["exception_detail", 0, "type"]
          assert_equal "StandardError", report.dig(*exception_class_dig_args)
        end
      end
    end

    context "on empty org" do
      test "returns false if org has neither configs or statuses" do
        refute @empty_org.trigger_security_center_reconciliation
      end

      test "returns true if org has orphan record in configs table" do
        random_repo = create :repository
        create(:repository_security_center_config, owner_id: @empty_org, repository: random_repo)
        assert @empty_org.trigger_security_center_reconciliation
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "returns true if org has orphan record in statuses table" do
        random_repo = create :repository
        create(:repository_security_center_status, :secret_scanning, :not_enrolled, owner_id: @empty_org, repository: random_repo)
        assert @empty_org.trigger_security_center_reconciliation
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "queues job" do
        refute @empty_org.trigger_security_center_reconciliation
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "does not queue job within window" do
        @empty_org.trigger_security_center_reconciliation
        Timecop.travel 1.day.from_now do
          @empty_org.trigger_security_center_reconciliation
        end
        assert_enqueued_jobs 1, only: SecurityCenter::OwnerReconciliationJob
      end

      test "queues job beyond window" do
        @empty_org.trigger_security_center_reconciliation
        Timecop.travel 8.days.from_now do
          @empty_org.trigger_security_center_reconciliation
        end
        assert_enqueued_jobs 2, only: SecurityCenter::OwnerReconciliationJob
      end

      test "does not throw if GitHub.kv raises error" do
        SecurityCenter::KV.store
          .stubs(:set)
          .raises(StandardError.new("test error"))
        Failbot.reports.clear

        @empty_org.trigger_security_center_reconciliation

        assert_equal 1, Failbot.reports.size
        Failbot.reports.each do |report|
          exception_class_dig_args = GitHub.enterprise? ? ["class"] : ["exception_detail", 0, "type"]
          assert_equal "StandardError", report.dig(*exception_class_dig_args)
        end
      end
    end
  end
end
