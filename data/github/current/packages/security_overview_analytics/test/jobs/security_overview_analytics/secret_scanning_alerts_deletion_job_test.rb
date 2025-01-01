# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class SecretScanningAlertsDeletionJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
      @now = Time.current
      @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@now.utc)
    end

    context "#perform" do
      test "does nothing if repository fails tenant validation" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
        SecretScanningAlertRevision.expects(:upsert_revision).never
        SecretScanningAlertRevision.expects(:delete_alert_revisions).never

        perform_enqueued_jobs only: SecretScanningAlertsDeletionJob do
          assert_nothing_raised do
            SecretScanningAlertsDeletionJob.perform_later(repository_id: @repo.id, alert_numbers: [1, 2])
          end
        end

        assert_empty SecretScanningAlertRevision.all
        assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alerts_deletion.skipped", tags: ["reason:tenant_not_in_scope"]
      end

      test "does nothing if repository owned by a non-emu but properly handles emu" do
        user = create(:user)
        repo = create(:repository, owner: user, force_user_owned: true)

        if TestEnv.test_with_all_emus?
          create(
            :soa_secret_scanning_alert_revision,
            repository_id: repo.id,
            alert_number: 1
          )

          assert SecretScanningAlertRevision.where(repository_id: repo.id, alert_number: 1).first

          SecretScanningAlertRevision.expects(:upsert_revision).never
          perform_enqueued_jobs only: SecretScanningAlertsDeletionJob do
            assert_nothing_raised do
              SecretScanningAlertsDeletionJob.perform_later(repository_id: repo.id, alert_numbers: [1])
            end
          end

          assert_empty SecretScanningAlertRevision.where(repository_id: repo.id, alert_number: 1).to_a
        else
          SecretScanningAlertRevision.expects(:upsert_revision).never
          SecretScanningAlertRevision.expects(:delete_alert_revisions).never

          perform_enqueued_jobs only: SecretScanningAlertsDeletionJob do
            assert_nothing_raised do
              SecretScanningAlertsDeletionJob.perform_later(repository_id: repo.id, alert_numbers: [1, 2])
            end
          end

          assert_empty SecretScanningAlertRevision.all
          assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alerts_deletion.skipped", tags: ["reason:not_org_or_emu_owned_repo"]
        end
      end

      test "does nothing if repository is soft-deleted" do
        SecretScanningAlertRevision.expects(:upsert_revision).never
        SecretScanningAlertRevision.expects(:delete_alert_revisions).never

        repo = create(:deleted_repository, owner: @org)
        perform_enqueued_jobs only: SecretScanningAlertsDeletionJob do
          assert_nothing_raised do
            SecretScanningAlertsDeletionJob.perform_later(repository_id: repo.id, alert_numbers: [1, 2])
          end
        end

        assert_empty SecretScanningAlertRevision.all
        assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alerts_deletion.skipped", tags: ["reason:repository_deleted"]
      end

      test "deletes alerts data" do
        create(
          :soa_secret_scanning_alert_revision,
          repository_id: @repo.id,
          alert_number: 1
        )
        assert SecretScanningAlertRevision.where(repository_id: @repo.id, alert_number: 1).first

        SecretScanningAlertRevision.expects(:upsert_revision).never
        perform_enqueued_jobs only: SecretScanningAlertsDeletionJob do
          assert_nothing_raised do
            SecretScanningAlertsDeletionJob.perform_later(repository_id: @repo.id, alert_numbers: [1])
          end
        end

        assert_empty SecretScanningAlertRevision.where(repository_id: @repo.id, alert_number: 1).to_a
      end
    end
  end
end
