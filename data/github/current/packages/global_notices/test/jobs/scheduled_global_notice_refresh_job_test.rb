# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

unless GitHub.enterprise? || GitHub.multi_tenant_enterprise?
  class ScheduledGlobalNoticeRefreshJobTest < GitHub::TestCase
    include JobTestHelper

    def create_year_old_recovery_codes_user
      user = create(:user, :two_factor_enabled, :established_sign_in_history)
      create(:authentication_record, user: user)
      user.two_factor_credential.update(created_at: 2.years.ago, recovery_codes_viewed: true)
      user.global_notice.destroy! if user.global_notice.persisted?
      user.reload

      user
    end

    def create_one_verified_email_user
      user = create(:user, :verified)
      create(:authentication_record, user: user)
      user.global_notice.destroy! if user.global_notice.persisted?
      user.reload

      user
    end

    setup do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.flipper[:disable_scheduled_global_notice_refresh].disable
    end

    fixtures do
      @user = create_year_old_recovery_codes_user
    end

    context "lock" do
      test "the job can only be queued once" do
        assert_enqueued_jobs 1 do
          ScheduledGlobalNoticeRefreshJob.perform_later
          ScheduledGlobalNoticeRefreshJob.perform_later
          ScheduledGlobalNoticeRefreshJob.perform_later
        end
      end

      test "uses the default lock key" do
        job = ScheduledGlobalNoticeRefreshJob.new
        assert_equal ActiveJob::LockingJob::DEFAULT_LOCK_KEY, job.lock_key
      end
    end

    context "schedule" do
      test "runs once per 2 hours" do
        job = ScheduledGlobalNoticeRefreshJob
        assert_equal 2.hours, job.schedule_options[:interval]
      end
    end

    context "retry" do
      test "on throttler error" do
        assert_retry_on_throttler_error(job: ScheduledGlobalNoticeRefreshJob)
      end

      test "on dirty exit" do
        assert_retry_on_dirty_exit(job: ScheduledGlobalNoticeRefreshJob)
      end
    end

    context "feature flagging" do
      test "does nothing when killswitch FF is enabled" do
        GitHub.flipper[:disable_scheduled_global_notice_refresh].enable
        @user.global_notice.unset # create empty global_notice row
        assert @user.global_notice.persisted?
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
        assert_nil @user.global_notice.last_checked_at

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_nil @user.global_notice.last_checked_at
      end
    end

    context "general behavior" do
      test "updates active users with global notice row" do
        @user.global_notice.unset # create empty global_notice row
        assert @user.global_notice.persisted?
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
        assert_nil @user.global_notice.last_checked_at

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert @user.global_notice.persisted?
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
        assert @user.global_notice.last_checked_at
      end

      test "doesn't update active users when they have higher priority global notice row" do
        @user.global_notice.set(:spammy)
        assert @user.global_notice.persisted?
        assert_nil @user.global_notice.last_checked_at

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert @user.global_notice.persisted?
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :spammy
        assert @user.global_notice.last_checked_at
      end

      test "last_checked is still updated when user has higher priority global notice row" do
        @user.global_notice.set(:spammy)
        assert @user.global_notice.persisted?
        assert_nil @user.global_notice.last_checked_at

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert @user.global_notice.persisted?
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :spammy
        assert @user.global_notice.last_checked_at
      end

      test "updates active users last_checked_at when they don't meet any notice conditions" do
        @user.two_factor_credential.update(created_at: 2.days.ago)
        @user.global_notice.unset
        assert @user.global_notice.persisted?
        assert_nil @user.global_notice.last_checked_at

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert @user.global_notice.persisted?
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
        assert @user.global_notice.last_checked_at
      end

      test "creates row for active users without global notice row" do
        refute @user.global_notice.persisted?
        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.reload
        assert @user.global_notice.persisted?
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
        assert @user.global_notice.last_checked_at
      end

      test "creates row for active users that don't meet any notice conditions" do
        @user.two_factor_credential.update(created_at: 2.days.ago)
        refute @user.global_notice.persisted?

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.reload
        assert @user.global_notice.persisted?
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
        assert @user.global_notice.last_checked_at
      end

      test "create and update both set utc timezone" do
        user2 = create_year_old_recovery_codes_user
        user2.global_notice.unset
        refute @user.global_notice.persisted?
        assert_nil @user.global_notice.last_checked_at
        assert_nil user2.global_notice.last_checked_at

        Timecop.freeze(Time.current.utc) do
          ScheduledGlobalNoticeRefreshJob.perform_now
          @user.reload
          user2.reload
          assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
          assert_equal GlobalNoticeNext.new(viewer: user2).current_notice_name, :year_old_recovery_codes
          assert @user.global_notice.last_checked_at
          assert user2.global_notice.last_checked_at
        end
      end

      test "update updates existing last_checked_at in utc timezone" do
        @user.global_notice.unset
        @user.global_notice.last_checked_at = 2.weeks.ago
        @user.global_notice.save
        assert @user.global_notice.persisted?

        Timecop.freeze(Time.current.utc) do
          ScheduledGlobalNoticeRefreshJob.perform_now
          @user.reload
          assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
          assert @user.global_notice.last_checked_at > 1.week.ago
        end
      end

      test "expected queries" do
        user2 = create_year_old_recovery_codes_user
        user2.global_notice.unset # one user with global_notice row
        refute @user.global_notice.persisted? # one user without

        expected_queries = { user_sessions: 2, two_factor_credentials: 1, global_notices: 7, user_emails: 1 }

        assert_query_count_per_table(expected_queries) do
          ScheduledGlobalNoticeRefreshJob.perform_now
        end

        @user.reload
        user2.reload
        assert @user.global_notice.last_checked_at
        assert user2.global_notice.last_checked_at
      end

      test "skips duplicate updates when user has multiple sessions and a global_notice row" do
        create(:authentication_record, user: @user)
        create(:authentication_record, user: @user)
        @user.global_notice.unset
        assert @user.global_notice.persisted?

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert @user.global_notice.persisted?
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
        assert @user.global_notice.last_checked_at
        assert_equal GitHub.dogstats.distributions("scheduled_global_notice_refresh_job.processed_count").count, 1
      end

      test "skips duplicate updates when user has multiple sessions and no global_notice row" do
        create(:authentication_record, user: @user)
        create(:authentication_record, user: @user)
        refute @user.global_notice.persisted?

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.reload
        assert @user.global_notice.persisted?
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
        assert @user.global_notice.last_checked_at
        assert_equal GitHub.dogstats.distributions("scheduled_global_notice_refresh_job.processed_count").count, 1
      end
    end

    context "batching" do
      test "batches" do
        user2 = create_year_old_recovery_codes_user
        user3 = create_year_old_recovery_codes_user
        user4 = create_year_old_recovery_codes_user

        ScheduledGlobalNoticeRefreshJob.stub_const(:BATCH_SIZE, 1) do
          ScheduledGlobalNoticeRefreshJob.perform_now
        end
        @user.reload
        assert @user.global_notice.persisted?
        assert user2.global_notice.persisted?
        assert user3.global_notice.persisted?
        assert user4.global_notice.persisted?
        assert @user.global_notice.last_checked_at
        assert user2.global_notice.last_checked_at
        assert_equal GitHub.dogstats.increments("scheduled_global_notice_refresh_job.batch.processed").count, 4
        assert_equal GitHub.dogstats.distributions("scheduled_global_notice_refresh_job.processed_count")[0].value, 4
      end

      test "batch updates are handled properly for duplicates" do
        create(:authentication_record, user: @user)
        @user.global_notice.unset

        ScheduledGlobalNoticeRefreshJob.stub_const(:BATCH_SIZE, 1) do
          ScheduledGlobalNoticeRefreshJob.perform_now
        end
        @user.reload
        assert @user.global_notice.persisted?
        assert @user.global_notice.last_checked_at
        assert_equal GitHub.dogstats.distributions("scheduled_global_notice_refresh_job.processed_count")[0].value, 1
      end

      test "exits early after hitting job limit with multiple batches" do
        user2 = create_year_old_recovery_codes_user
        user3 = create_year_old_recovery_codes_user
        user4 = create_year_old_recovery_codes_user

        ScheduledGlobalNoticeRefreshJob.stub_const(:BATCH_SIZE, 1) do
          job = ScheduledGlobalNoticeRefreshJob.new
          job.stubs(:job_limit).returns(2)
          job.perform_now
        end

        assert_equal GitHub.dogstats.distributions("scheduled_global_notice_refresh_job.processed_count")[0].value, 2
        assert_equal GitHub.dogstats.increments("scheduled_global_notice_refresh_job.batch.processed").count, 2
      end
    end

    context "year_old_recovery_codes" do
      test "doesn't update user with new two_factor_credential" do
        @user.two_factor_credential.update(created_at: 1.month.ago)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "doesn't update user with old two_factor_credential that isn't elligible" do
        # they saved recovery codes over a year ago but more than a year after enrolling
        @user.two_factor_credential.update(created_at: 5.years.ago)
        @user.two_factor_credential.update(recovery_codes_last_downloaded_at: 3.years.ago)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "does update user with old two_factor_credential that has saved codes but not recently enough" do
        # they saved recovery codes over a year ago but more than a year after enrolling
        @user.two_factor_credential.update(created_at: 2.years.ago)
        @user.two_factor_credential.update(recovery_codes_last_downloaded_at: 2.years.ago + 10.days)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
      end

      test "doesn't update user who has printed recovery codes" do
        @user.two_factor_credential.update(recovery_codes_last_downloaded_at: 1.month.ago)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "doesn't update user who has downloaded recovery codes" do
        @user.two_factor_credential.update(recovery_codes_last_printed_at: 1.month.ago)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name
      end

      test "does update user who has downloaded recovery codes 2 years ago" do
        @user.two_factor_credential.update(recovery_codes_last_printed_at: 2.years.ago)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
      end

      test "does update user who has downloaded and printed recovery codes 2 years ago" do
        @user.two_factor_credential.update(recovery_codes_last_printed_at: 2.years.ago)
        @user.two_factor_credential.update(recovery_codes_last_downloaded_at: 2.years.ago)

        @user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: @user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        @user.global_notice.reload
        assert_equal GlobalNoticeNext.new(viewer: @user).current_notice_name, :year_old_recovery_codes
      end
    end

    context "one_verified_email" do
      test "doesn't update user who has multiple verified emails" do
        verified_email_user = create_one_verified_email_user

        verified_email_user.emails.create!(state: "verified", email: "verified@github.com")
        verified_email_user.global_notice.unset

        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        verified_email_user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name
      end

      test "doesn't update user who has no verified emails" do
        verified_email_user = create_one_verified_email_user

        verified_email_user.emails.first.update!(state: "unverified")
        verified_email_user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        verified_email_user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name
      end

      test "doesn't update user who has multiple verified emails and one was recent" do
        verified_email_user = create_one_verified_email_user
        verified_email_user.emails.create!(state: "verified", email: "verified@github.com", verified_at: 2.months.ago)
        verified_email_user.emails.create!(state: "verified", email: "verified1@github.com", verified_at: 1.day.ago)

        verified_email_user.global_notice.unset

        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name
        ScheduledGlobalNoticeRefreshJob.perform_now
        verified_email_user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name
      end

      test "doesn't update user who recently verified their email" do
        verified_email_user = create_one_verified_email_user
        assert_equal verified_email_user.emails.verified.count, 1
        verified_email_user.emails.verified.first.update!(verified_at: 1.day.ago)
        verified_email_user.global_notice.unset

        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        verified_email_user.global_notice.reload
        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name
      end

      test "does update user who has one verified email" do
        verified_email_user = create_one_verified_email_user

        assert_equal verified_email_user.emails.verified.count, 1
        verified_email_user.emails.verified.first.update!(verified_at: 2.months.ago)
        verified_email_user.global_notice.unset
        assert_nil GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name

        ScheduledGlobalNoticeRefreshJob.perform_now
        verified_email_user.global_notice.reload
        assert_equal GlobalNoticeNext.new(viewer: verified_email_user).current_notice_name, :one_verified_email
      end
    end
  end
end
