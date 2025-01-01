# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Backfill
    class AlertReopenedAtJobTest < GitHub::TestCase
      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)
        @repo = create(:private_repository, owner: @org)
      end

      setup do
        enable_feature_flag(:security_center_backfill_alert_reopened_at)
        GitHub.flipper[:soa_backfill_alert_reopened_at_job_restraint_lock_num_concurrent_jobs].enable_percentage_of_actors(10.0)
        GitHub.flipper[:soa_backfill_alert_reopened_at_job_restraint_lock_ttl_minutes].enable_percentage_of_actors(60.0)
      end

      context 'when feature flag "security_center_backfill_code_scanning_alert_number" is disabled' do
        test "it does not perform the job" do
          disable_feature_flag(:security_center_backfill_alert_reopened_at)

          create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: true
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231202,
            next_revision_date_id: 20231204,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 2).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231204,
            next_revision_date_id: 20231205,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: nil
          )

          assert_no_performed_jobs(only: AlertReopenedAtJob) do
            AlertReopenedAtJob.perform_now(repository_id: @repo.id, owner_id: @org.id, feature: "code_scanning")
          end
        end
      end

      context "when arguments are missing" do
        test "it raises an error when repository_id is blank" do
          assert_raises(ArgumentError) do
            AlertReopenedAtJob.perform_later(owner_id: @org.id, feature: "code_scanning")
          end
        end

        test "it raises an error when feature is blank" do
          assert_raises(ArgumentError) do
            AlertReopenedAtJob.perform_later(owner_id: @org.id, repository_id: @repo.id)
          end
        end
      end

      context "when feature argument is invalid" do
        test "it raises an error" do
          assert_raises(ArgumentError) do
            AlertReopenedAtJob.perform_later(owner_id: @org.id, repository_id: @repo.id, feature: "invalid_feature")
          end
        end
      end

      context "when dry_run mode is on" do
        test "it performs but does not update alert_reopened_at column" do
          create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: true
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231202,
            next_revision_date_id: 20231204,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 2).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231204,
            next_revision_date_id: 20231205,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: nil
          )

          assert_no_changes(
            -> do
              CodeScanningAlertRevision
                .where(repository_id: @repo.id)
                .order(:id)
                .pluck(:alert_number)
            end
          ) do
            AlertReopenedAtJob.perform_now(repository_id: @repo.id, owner_id: @org.id, feature: "code_scanning", dry_run: true)
          end
        end
      end

      context "when there are only unresolved alerts in chain" do
        test "it updates outdated alert_reopened_at columns" do
          initial_revision = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: false
          )
          reopened_revision1 = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231202,
            next_revision_date_id: 20231203,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 2).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc
          )
          reopened_revision2 = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231203,
            next_revision_date_id: 20231204,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 3).utc,
            alert_reopened_at: DateTime.new(2023, 12, 3).utc
          )
          other_metadata_change_revision = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231204,
            next_revision_date_id: 20231205,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc # outdated date from reopened_revision1
          )
          other_metadata_change_revision2 = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231205,
            next_revision_date_id: 20231206,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: nil
          )
          reopened_revision3 = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231206,
            next_revision_date_id: 20231207,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 5).utc,
            alert_reopened_at: DateTime.new(2023, 12, 5).utc
          )
          final_revision = create(
            :soa_code_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231207,
            next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 6).utc,
            alert_reopened_at: nil
          )

          records = [
            initial_revision,
            other_metadata_change_revision,
            other_metadata_change_revision2,
            reopened_revision1,
            reopened_revision2,
            reopened_revision3,
            final_revision
          ]

          perform_enqueued_jobs only: AlertReopenedAtJob do
            assert_nothing_raised do
              AlertReopenedAtJob.perform_later(repository_id: @repo.id, owner_id: @org.id, feature: "code_scanning")
            end
          end

          records.map(&:reload)
          assert_equal other_metadata_change_revision.alert_reopened_at, reopened_revision2.alert_reopened_at
          assert_equal other_metadata_change_revision2.alert_reopened_at, reopened_revision2.alert_reopened_at
          assert_equal final_revision.alert_reopened_at, reopened_revision3.alert_reopened_at
        end
      end

      context "when there are only resolved alerts in chain" do
        test "it updates outdated alert_reopened_at columns" do
          initial_revision = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: true
          )
          reopened_revision1 = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231202,
            next_revision_date_id: 20231203,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 2).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc
          )
          reopened_revision2 = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231203,
            next_revision_date_id: 20231204,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 3).utc,
            alert_reopened_at: DateTime.new(2023, 12, 3).utc
          )
          other_metadata_change_revision = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231204,
            next_revision_date_id: 20231205,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc # from reopened_revision1
          )
          other_metadata_change_revision2 = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231205,
            next_revision_date_id: 20231206,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: nil
          )
          reopened_revision3 = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231206,
            next_revision_date_id: 20231207,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 5).utc,
            alert_reopened_at: DateTime.new(2023, 12, 5).utc
          )
          final_revision = create(
            :soa_secret_scanning_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231207,
            next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 6).utc,
            alert_reopened_at: nil
          )

          records = [
            initial_revision,
            other_metadata_change_revision,
            other_metadata_change_revision2,
            reopened_revision1,
            reopened_revision2,
            reopened_revision3,
            final_revision
          ]

          perform_enqueued_jobs only: AlertReopenedAtJob do
            assert_nothing_raised do
              AlertReopenedAtJob.perform_later(repository_id: @repo.id, owner_id: @org.id, feature: "secret_scanning")
            end
          end

          records.map(&:reload)
          assert_equal other_metadata_change_revision.alert_reopened_at, reopened_revision2.alert_reopened_at
          assert_equal other_metadata_change_revision2.alert_reopened_at, reopened_revision2.alert_reopened_at
          assert_equal final_revision.alert_reopened_at, reopened_revision3.alert_reopened_at
        end
      end

      context "when there is a mix of resolved and unresolved alerts in the chain" do
        test "it updates outdated alert_reopened_at columns" do
          initial_revision = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: true
          )
          reopened_revision1 = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231202,
            next_revision_date_id: 20231203,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 2).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc
          )
          reopened_revision2 = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231203,
            next_revision_date_id: 20231204,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 3).utc,
            alert_reopened_at: nil
          )
          other_metadata_change_revision = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231204,
            next_revision_date_id: 20231205,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc # outdated date from reopened_revision1
          )
          other_metadata_change_revision2 = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231205,
            next_revision_date_id: 20231206,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: nil
          )
          reopened_revision3 = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231206,
            next_revision_date_id: 20231207,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 5).utc,
            alert_reopened_at: DateTime.new(2023, 12, 5).utc
          )
          final_revision = create(
            :soa_dependabot_alert_revision,
            repository_id: @repo&.id,
            alert_number: 1,
            date_id: 20231207,
            next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 6).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc # outdated date from reopened_revision1
          )

          records = [
            initial_revision,
            other_metadata_change_revision,
            other_metadata_change_revision2,
            reopened_revision1,
            reopened_revision2,
            reopened_revision3,
            final_revision
          ]

          perform_enqueued_jobs only: AlertReopenedAtJob do
            assert_nothing_raised do
              AlertReopenedAtJob.perform_later(repository_id: @repo.id, owner_id: @org.id, feature: "dependabot")
            end
          end

          records.map(&:reload)
          assert_equal reopened_revision2.alert_reopened_at, reopened_revision2.alert_updated_at
          assert_equal other_metadata_change_revision.alert_reopened_at, reopened_revision2.alert_reopened_at
          assert_equal other_metadata_change_revision2.alert_reopened_at, reopened_revision2.alert_reopened_at
          assert_equal final_revision.alert_reopened_at, reopened_revision3.alert_reopened_at
        end
      end

      context "batching jobs" do
        test "queues a second job based on revision ids" do
          repo = create(:private_repository, owner: @org)
          create(
            :soa_code_scanning_alert_revision,
            repository_id: repo.id,
            alert_number: 1,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: true,
            alert_reopened_at: nil # no alert_reopened_at, so shouldn't get picked up for processing
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: repo.id,
            alert_number: 1,
            date_id: 20231202,
            next_revision_date_id: 20231204,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 2).utc,
            alert_reopened_at: DateTime.new(2023, 12, 2).utc
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: repo.id,
            alert_number: 1,
            date_id: 20231204,
            next_revision_date_id: 20231205,
            alert_resolved: true,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: DateTime.new(2023, 12, 4).utc,
          )
          create(
            :soa_code_scanning_alert_revision,
            repository_id: repo.id,
            alert_number: 2,
            date_id: 20231201,
            next_revision_date_id: 20231202,
            alert_resolved: false,
            alert_updated_at: DateTime.new(2023, 12, 4).utc,
            alert_reopened_at: DateTime.new(2023, 12, 4).utc,
          )

          BatchedJob.stub_const(:BATCH_SIZE, 2) do
            # validate that we queue a second job
            AlertReopenedAtJob.expects(:perform_later)
            .with { |kwargs| kwargs[:offset_item_id] == [1, 20231205] }
            .once

            AlertReopenedAtJob.perform_now(repository_id: repo.id, owner_id: @org.id, feature: "code_scanning")
          end
        end
      end

      private

      def feature_model(feature)
        def feature_model(feature)
          case feature
          when "code_scanning"
            :soa_code_scanning_alert_revision
          when "secret_scanning"
            :soa_secret_scanning_alert_revision
          when "dependabot"
            :soa_dependabot_alert_revision
          else
            nil
          end
        end
      end
    end
  end
end
