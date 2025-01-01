# typed: true
# frozen_string_literal: true

require "test_helper"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class SecretScanningAlertRevisionIngestionJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert

    fixtures do
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
      @now = Time.current
    end

    context "#perform" do
      test "does nothing if repository fails tenant validation" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
        SecretScanningAlertRevision.expects(:upsert_revision).never

        perform_enqueued_jobs only: SecretScanningAlertRevisionIngestionJob do
          assert_nothing_raised do
            SecretScanningAlertRevisionIngestionJob.perform_later(
              alert: alert_payload(repository_id: @repo.id, alert_number: 1),
              event_time: @now,
              source_event: "security_overview_analytics.test",
            )
          end
        end

        assert_empty SecretScanningAlertRevision.all
        assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped", tags: ["reason:tenant_not_in_scope"]
      end

      test "does nothing if repository owned by a non-emu but properly handles emu" do
        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)
        if TestEnv.test_with_all_emus?
          assert_empty SecretScanningAlertRevision.all

          perform_enqueued_jobs only: SecretScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              SecretScanningAlertRevisionIngestionJob.perform_later(
                alert: alert_payload(repository_id: repo.id, alert_number: 1),
                event_time: @now,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert SecretScanningAlertRevision.where(repository_id: repo.id, alert_number: 1).first
        else
          SecretScanningAlertRevision.expects(:upsert_revision).never

          perform_enqueued_jobs only: SecretScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              SecretScanningAlertRevisionIngestionJob.perform_later(
                alert: alert_payload(repository_id: repo.id, alert_number: 1),
                event_time: @now,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_empty SecretScanningAlertRevision.all
          assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped", tags: ["reason:not_org_or_emu_owned_repo"]
        end
      end

      test "does nothing if repository is soft-deleted" do
        SecretScanningAlertRevision.expects(:upsert_revision).never

        repo = create(:deleted_repository, owner: @org)
        perform_enqueued_jobs only: SecretScanningAlertRevisionIngestionJob do
          assert_nothing_raised do
            SecretScanningAlertRevisionIngestionJob.perform_later(
              alert: alert_payload(repository_id: repo.id, alert_number: 1),
              event_time: @now,
              source_event: "security_overview_analytics.test",
            )
          end
        end

        assert_empty SecretScanningAlertRevision.all
        assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped", tags: ["reason:repository_deleted"]
      end

      test "upserts alert revision" do
        assert_empty SecretScanningAlertRevision.all

        perform_enqueued_jobs only: SecretScanningAlertRevisionIngestionJob do
          assert_nothing_raised do
            SecretScanningAlertRevisionIngestionJob.perform_later(
              alert: alert_payload(repository_id: @repo.id, alert_number: 1),
              event_time: @now,
              source_event: "security_overview_analytics.test",
            )
          end
        end

        assert SecretScanningAlertRevision.where(repository_id: @repo.id, alert_number: 1).first
      end

      test "can upserts alert revision with force_rewrite" do
        assert_empty SecretScanningAlertRevision.all

        SecretScanningAlertRevision.expects(:upsert_revision).with(anything, has_entries(force_rewrite: true)).once

        perform_enqueued_jobs only: SecretScanningAlertRevisionIngestionJob do
          assert_nothing_raised do
            SecretScanningAlertRevisionIngestionJob.perform_later(
              alert: alert_payload(repository_id: @repo.id, alert_number: 1),
              event_time: @now,
              force_rewrite: true,
              source_event: "security_overview_analytics.test",
            )
          end
        end
      end

      context "telemetry" do
        context "when source event is incremental" do
          test "emits repository updated metric" do
            source_event = "hydro.schemas.github.security_center.v0.insightsentitybatch.secret_scanning_alert_upsert"
            alert = alert_payload(repository_id: @repo.id, alert_number: 42)
            SecretScanningAlertRevisionIngestionJob.perform_now(alert:, event_time: @now, source_event:)
            assert_dogstats_distribution(1, "security_overview_analytics.updated.dist", tags: ["source_event:#{source_event}"])
          end
        end

        context "when source event is initialization" do
          test "emits repository updated metric" do
            source_event = Initialization::TenantBaseJob::INITIALIZATION_EVENT
            alert = alert_payload(repository_id: @repo.id, alert_number: 42)
            SecretScanningAlertRevisionIngestionJob.perform_now(alert:, event_time: @now, source_event:)
            refute_dogstats_distribution("security_overview_analytics.updated.dist")
          end
        end

        context "when source event is reconciliation" do
          test "emits repository updated metric" do
            source_event = Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT
            alert = alert_payload(repository_id: @repo.id, alert_number: 42)
            SecretScanningAlertRevisionIngestionJob.perform_now(alert:, event_time: @now, source_event:)
            refute_dogstats_distribution("security_overview_analytics.updated.dist")
          end
        end
      end
    end

    private

    sig { params(repository_id: Integer, alert_number: Integer, kwargs: T.untyped).returns(SecretScanningAlert) }
    def alert_payload(repository_id:, alert_number:, **kwargs)
      t = Time.now

      kwargs = {
        repository_id:,
        number: alert_number,
        created_at: t, # AnyTime # datetime(3) NOT NULL,
        updated_at: t, # AnyTime # datetime(3) NOT NULL,
        resolved: false, # T::Boolean # tinyint(1) NOT NULL,
        resolved_at: nil, # T.nilable(AnyTime) # datetime(3) DEFAULT NULL,
        resolution: nil, # T.nilable(Integer) # tinyint unsigned DEFAULT NULL,
        token_type: "cp_1", # String: varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        token_type_provider: "CP", # String: varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        slug: "custom_pattern", # String: varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        **kwargs,
      }

      SecretScanningAlert.new(**T.unsafe(kwargs))
    end
  end
end
