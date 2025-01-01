# typed: strict
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class OrganizationReconciliationJobTest < GitHub::TestCase
      include DogstatsTestHelpers

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)

        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::CodeScanningAlert).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(true)

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        end
      end

      context "#perform" do
        test "it does not enqueue initialization job for feature that is not available on GHES", enterprise_only: true do
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)
          RepositoryMetadataDeviationDetectionJob.expects(:perform_later).once
          RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).once
          DependabotRepositoriesDeviationDetectionJob.expects(:perform_later).once
          CodeScanningRepositoriesDeviationDetectionJob.expects(:perform_later).never
          SecretScanningRepositoriesDeviationDetectionJob.expects(:perform_later).once

          org = create(:organization)
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            assert_nothing_raised do
              OrganizationReconciliationJob.perform_later(organization_id: org.id)
            end
          end
        end

        test "does not start reconciliation session if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          RepositoryMetadataDeviationDetectionJob.expects(:perform_later).never
          RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).never

          org = create(:organization)
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            assert_nothing_raised do
              OrganizationReconciliationJob.perform_later(organization_id: org.id)
            end
          end
          assert_dogstats_increment 5, "security_overview_analytics.organization_reconciliation.skipped"
        end

        test "raises if organization is not found" do
          org = create(:organization)
          org_id = org.id
          org.destroy!

          perform_enqueued_jobs only: OrganizationReconciliationJob do
            assert_raises ActiveRecord::RecordNotFound do
              OrganizationReconciliationJob.perform_later(organization_id: org_id)
            end
          end
        end

        context "no type is provided" do
          test "enqueues deviation detection job for all metric types" do
            org = create(:organization)
            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
            # TODO - assert other metric types are enqueued

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id)
              end
            end
            refute_dogstats_increment "security_overview_analytics.organization_reconciliation.skipped"
          end
        end

        context "a specific metric type is provided" do
          test "enqueues repository metadata deviation detection job" do
            org = create(:organization)
            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).never
            # TODO - assert other metric types

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "repository_metadata")
              end
            end
            refute_dogstats_increment "security_overview_analytics.organization_reconciliation.skipped"
          end

          test "enqueues feature status deviation detection job" do
            org = create(:organization)
            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).never
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once
            # TODO - assert other metric types

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "feature_enablement")
              end
            end
            refute_dogstats_increment "security_overview_analytics.organization_reconciliation.skipped"
          end

          test "enqueues dependabot alerts deviation detection job" do
            org = create(:organization)
            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).never
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).never
            DependabotRepositoriesDeviationDetectionJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "dependabot_alerts")
              end
            end
            refute_dogstats_increment "security_overview_analytics.organization_reconciliation.skipped"
          end

          test "enqueues code scanning alerts deviation detection job" do
            org = create(:organization)
            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).never
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).never
            CodeScanningRepositoriesDeviationDetectionJob.expects(:perform_later).with(has_entries(organization_id: org.id)).once

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "code_scanning_alert")
              end
            end
            refute_dogstats_increment "security_overview_analytics.organization_reconciliation.skipped"
          end

          test "enqueues secret scanning alerts deviation detection job" do
            org = create(:organization)
            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).never
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).never
            SecretScanningRepositoriesDeviationDetectionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:organization_id] == org.id }
              .once

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "secret_scanning_alert")
              end
            end
            refute_dogstats_increment "security_overview_analytics.organization_reconciliation.skipped"
          end

          test "don't enqueue fanout job if metric type is not initialized" do
            org = create(:organization)
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::CodeScanningAlert).returns(false)
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(false)
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(false)

            RepositoryMetadataDeviationDetectionJob.expects(:perform_later).never
            RepositoryFeatureStatusDeviationDetectionJob.expects(:perform_later).never
            DependabotRepositoriesDeviationDetectionJob.expects(:perform_later).never
            CodeScanningRepositoriesDeviationDetectionJob.expects(:perform_later).never
            SecretScanningRepositoriesDeviationDetectionJob.expects(:perform_later).never

            perform_enqueued_jobs only: OrganizationReconciliationJob do
              assert_nothing_raised do
                OrganizationReconciliationJob.perform_later(organization_id: org.id)
              end
            end
            assert_dogstats_increment 5, "security_overview_analytics.organization_reconciliation.skipped"
          end
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same org" do
          org = create(:organization)
          assert_enqueued_jobs 1, only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: org.id)
            OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "repository_metadata")
            OrganizationReconciliationJob.perform_later(organization_id: org.id, type: "repository_metadata")
          end
        end
      end
    end
  end
end
