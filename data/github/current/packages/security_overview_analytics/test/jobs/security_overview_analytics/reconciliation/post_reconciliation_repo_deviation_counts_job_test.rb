# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class PostReconciliationRepoDeviationCountsJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      Event = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent

      fixtures do
        @org = create(:business_plus_organization)
        @repo = create(:repository, owner: @org)
        @soa_repo = create(:security_overview_analytics_repository, repository: @repo)

        @vulnerable_version_range_1 = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm")
        @vulnerability_1 = create(:vulnerability, severity: "high")

        @vulnerable_version_range_2 = create(:vulnerable_version_range, affects: "ruby", fixed_in: "1", ecosystem: "npm")
        @vulnerability_2 = create(:vulnerability, severity: "high")
      end

      setup do
        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        end

        ::Repository.any_instance.stubs(:security_feature_configured?).returns(true)
      end

      context "dependabot" do
        test "emits telemetry when deviations found" do
          # Create a non-deviated alert
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range: @vulnerable_version_range_1,
            vulnerability: @vulnerability_1,
            affects: "package-1",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
          create_dbot_revision_from_alert(alert, @repo, updated_date_id)

          # Create a deviated alert (it's closed)
          alert_2 = create(:repository_vulnerability_alert,
            :fixed,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range: @vulnerable_version_range_2,
            vulnerability: @vulnerability_2,
            affects: "package-3",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert_2.updated_at&.utc.to_time)
          revision = create_dbot_revision_from_alert(alert_2, @repo, updated_date_id)
          revision.update!(alert_severity: :LOW, alert_resolved: false)

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "dependabot"
            )
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:dependabot"]
        end

        test "does not emit telemetry when no deviations found" do
          # Create non-deviated alerts
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range: @vulnerable_version_range_1,
            vulnerability: @vulnerability_1,
            affects: "package-1",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
          create_dbot_revision_from_alert(alert, @repo, updated_date_id)

          alert_2 = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range: @vulnerable_version_range_2,
            vulnerability: @vulnerability_2,
            affects: "package-3",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert_2.updated_at&.utc.to_time)
          create_dbot_revision_from_alert(alert_2, @repo, updated_date_id)

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "dependabot"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:dependabot"]
        end

        test "does not emit telemetry when dependabot isn't configured" do
          ::Repository.any_instance.stubs(:security_feature_configured?).with(:DEPENDABOT_ALERTS).returns(false)

          # Create a non-deviated alert
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range: @vulnerable_version_range_1,
            vulnerability: @vulnerability_1,
            affects: "package-1",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
          create_dbot_revision_from_alert(alert, @repo, updated_date_id)

          # Create a deviated alert (it's closed)
          alert_2 = create(:repository_vulnerability_alert,
            :fixed,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range: @vulnerable_version_range_2,
            vulnerability: @vulnerability_2,
            affects: "package-3",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert_2.updated_at&.utc.to_time)
          revision = create_dbot_revision_from_alert(alert_2, @repo, updated_date_id)
          revision.update!(alert_severity: :LOW, alert_resolved: false)

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "dependabot"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:dependabot"]
        end
      end

      context "secret-scanning" do
        test "emits telemetry when deviations found" do
          create_ss_revisions

          # TSS alert count response
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).with(
            GitHub::Proto::SecretScanning::Api::V2::GetTokensRequest.new({
              repo_selector: ::GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(repository_id: @repo.id),
              token_state: 1,
              low_confidence: false,
              sort_order: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_SORT_SERVICE_ENUM,
              page: 1,
              limit: 1
            }).to_h
          ).returns(Twirp::ClientResp.new(
            error: nil,
            data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
              tokens: [],
              unresolved_count: 1,
              resolved_count: 1
            )
          ))

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "secret-scanning"
            )
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:secret-scanning"]
        end

        test "does not emit telemetry when no deviations found" do
          create_ss_revisions

          # TSS alert count response
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).with(
            GitHub::Proto::SecretScanning::Api::V2::GetTokensRequest.new({
              repo_selector: ::GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(repository_id: @repo.id),
              token_state: 1,
              low_confidence: false,
              sort_order: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_SORT_SERVICE_ENUM,
              page: 1,
              limit: 1
            }).to_h
          ).returns(Twirp::ClientResp.new(
            error: nil,
            data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
              tokens: [],
              unresolved_count: 2,
              resolved_count: 0
            )
          ))

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "secret-scanning"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:secret-scanning"]
        end

        test "does not emit telemetry when TSS returns errors" do
          create_ss_revisions

          # TSS alert count response
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).with(
            GitHub::Proto::SecretScanning::Api::V2::GetTokensRequest.new({
              repo_selector: ::GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(repository_id: @repo.id),
              token_state: 1,
              low_confidence: false,
              sort_order: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_SORT_SERVICE_ENUM,
              page: 1,
              limit: 1
            }).to_h
          ).returns(Twirp::ClientResp.new(
            error: "some-error",
            data: nil
          ))

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "secret-scanning"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:secret-scanning"]
        end

        test "does not emit telemetry when secret scanning isn't configured" do
          ::Repository.any_instance.stubs(:security_feature_configured?).with(:SECRET_SCANNING).returns(false)

          create_ss_revisions

          # TSS alert count response
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "secret-scanning"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:secret-scanning"]
        end
      end

      context "code-scanning" do
        test "emits telemetry when deviations found" do
          create_cs_revisions

          # Turboscan alert count response
          GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries({
            repository_ids: [@repo.id],
            owner_ids: [@repo.owner.id]
          })).returns(Twirp::ClientResp.new(
            data: Turboscan::Proto::AlertsByRepoResponse.new({
              open_count: 1,
              resolved_count: 1,
              results: [
                Turboscan::Proto::RepoResult.new({ repository_id: @repo.id })
              ]
            })
          ))

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "code-scanning"
            )
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:code-scanning"]
        end

        test "does not emit telemetry when no deviations found" do
          create_cs_revisions

          # Turboscan alert count response
          GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries({
            repository_ids: [@repo.id],
            owner_ids: [@repo.owner.id]
          })).returns(Twirp::ClientResp.new(
            data: Turboscan::Proto::AlertsByRepoResponse.new({
              open_count: 2,
              resolved_count: 0,
              results: [
                Turboscan::Proto::RepoResult.new({ repository_id: @repo.id })
              ]
            })
          ))

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "code-scanning"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:code-scanning"]
        end

        test "does not emit telemetry when Turboscan returns errors" do
          create_cs_revisions

          # Turboscan alert count response
          GitHub::Turboscan.expects(:alerts_by_repo).once.with(has_entries({
            repository_ids: [@repo.id],
            owner_ids: [@repo.owner.id]
          })).returns(Twirp::ClientResp.new(
            error: "some-error",
            data: Turboscan::Proto::AlertsByRepoResponse.new({
              open_count: 1,
              resolved_count: 1,
              results: [
                Turboscan::Proto::RepoResult.new({ repository_id: @repo.id })
              ]
            })
          ))

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "code-scanning"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:code-scanning"]
        end

        test "does not emit telemetry when code scanning isn't configured" do
          ::Repository.any_instance.stubs(:security_feature_configured?).with(:CODE_SCANNING).returns(false)

          create_cs_revisions

          GitHub::Turboscan.expects(:alerts_by_repo).never

          assert_performed_jobs 1, only: PostReconciliationRepoDeviationCountsJob do
            PostReconciliationRepoDeviationCountsJob.perform_later(
              repository_id: @repo.id,
              owner_id: @repo.owner.id,
              feature: "code-scanning"
            )
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.post_reconciliation_deviations_found", tags: ["feature:code-scanning"]
        end
      end

      private

      def create_dbot_revision_from_alert(alert, repo, date_id)
        last_state_change_reason = alert.last_state_change_reason&.upcase&.to_sym
        alert_resolution = if last_state_change_reason.is_a?(Symbol)
          Event::LastStateChangeReason.resolve(last_state_change_reason) || Event::LastStateChangeReason::REASON_UNKNOWN
        end
        alert_resolution = nil if alert_resolution == Event::LastStateChangeReason::NO_REASON

        create(:security_overview_analytics_dependabot_alert_revision,
          repository_id: repo.id,
          date_id:,
          alert_number: alert.number,
          alert_resolved: !alert.open?,
          alert_resolved_at: !alert.open? ? alert.last_state_change_at : nil,
          alert_resolution:,
          alert_severity: alert.severity.upcase.to_sym,
          ghsa_id: alert.vulnerability.ghsa_id,
          dependency_scope: alert.dependency_scope.upcase.to_sym,
          ecosystem: alert.ecosystem,
          package_name: alert.package_name
        )
      end

      def create_cs_revisions
        a_week_ago = 1.week.ago.to_time
        two_days_ago = 2.days.ago.to_time
        now = Time.now

        # create a new revision (after `updated_after`)
        create(:soa_code_scanning_alert_revision,
          repository: @repo,
          alert_number: 2,
          date_id: Date.id_from_time(now),
          next_revision_date_id: Date::FUTURE_DATE_ID,
          alert_severity: "CRITICAL",
        )

        # create an earlier revision (before `updated_after`)
        date = create(:soa_date, date_value: two_days_ago)
        create(:soa_feature_status_revision, repository_metadata: @soa_repo, date: date, secret_scanning_enabled: true)
        create(:soa_code_scanning_alert_revision,
          repository: @repo,
          alert_number: 1,
          date: date,
          alert_created_at: a_week_ago,
          alert_updated_at: two_days_ago,
          alert_severity: "CRITICAL",
        )
      end

      def create_ss_revisions
        a_week_ago = 1.week.ago.to_time
        two_days_ago = 2.days.ago.to_time
        now = Time.now

        # create a new revision (after `updated_after`)
        create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 2,
          alert_type: "alert_type",
          alert_type_provider: "alert_type_provider",
          alert_type_slug: "alert_type_slug",
          alert_resolved: false,
          alert_created_at: a_week_ago,
          alert_updated_at: now,
          date: create(:security_overview_analytics_date, date_value: now)
        )

        # create an earlier revision (before `updated_after`)
        date = create(:soa_date, date_value: two_days_ago)
        create(:soa_feature_status_revision, repository_metadata: @soa_repo, date: date, secret_scanning_enabled: true)
        create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1,
          alert_type: "alert_type",
          alert_type_provider: "alert_type_provider",
          alert_type_slug: "alert_type_slug",
          alert_resolved: false,
          alert_created_at: a_week_ago,
          alert_updated_at: two_days_ago,
          date: date
        )
      end
    end
  end
end
