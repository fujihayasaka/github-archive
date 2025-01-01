# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAccountManagementDependencyTest < GitHub::TestCase
  fixtures do
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
  end

  context "last_active_timestamp" do
    test "returns nil if there is no activity" do
      user = create(:user)
      refute_predicate user.sessions, :any?
      refute_predicate user.events, :any?
      assert_nil user.last_active_timestamp, "should not have last active timestamp"
    end

    test "returns date of the most recent stratocaster event" do
      GitHub.flipper[:discard_stratocaster_fanout].disable
      last_event_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc
      last_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:29 -0700").utc

      Timecop.freeze(last_event_date) do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :full_creation, owner: @free_user }
      end

      Timecop.freeze(last_session_date) do
        create(:user_session, user: @free_user)
      end

      assert_equal last_event_date.in_time_zone, @free_user.last_active_timestamp
    end

    test "returns date of the most recent session activity" do
      GitHub.flipper[:discard_stratocaster_fanout].disable
      last_event_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc
      last_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:31 -0700").utc

      Timecop.freeze(last_event_date) do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :with_instrumentation, owner: @free_user }
      end

      Timecop.freeze(last_session_date) do
        create(:user_session, user: @free_user)
      end

      assert_equal last_session_date.in_time_zone, @free_user.last_active_timestamp
    end

    test "returns date of the most recent PAT access" do
      GitHub.flipper[:discard_stratocaster_fanout].disable
      last_event_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc
      last_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:31 -0700").utc
      last_pat_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:32 -0700").utc

      Timecop.freeze(last_event_date) do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :with_instrumentation, owner: @free_user }
      end

      Timecop.freeze(last_session_date) do
        create(:user_session, user: @free_user)
      end

      Timecop.freeze(last_pat_date) do
        pat = create :personal_token_oauth_access, user: @free_user
        pat.update!(accessed_at: last_pat_date)
      end

      assert_equal last_pat_date.in_time_zone, @free_user.last_active_timestamp
    end

    test "returns date of the most recent SSH key access" do
      GitHub.flipper[:discard_stratocaster_fanout].disable
      last_event_date   = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc
      last_session_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:31 -0700").utc
      last_pat_date     = Time.rfc2822("Tue, 15 Jul 2008 17:40:32 -0700").utc
      last_ssh_date     = Time.rfc2822("Tue, 15 Jul 2008 17:40:33 -0700").utc

      Timecop.freeze(last_event_date) do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        perform_enqueued_jobs(only: only) { create :repository, :with_instrumentation, owner: @free_user }
      end

      Timecop.freeze(last_session_date) do
        create(:user_session, user: @free_user)
      end

      Timecop.freeze(last_pat_date) do
        pat = create :personal_token_oauth_access, user: @free_user
        pat.update!(accessed_at: last_pat_date)
      end

      Timecop.freeze(last_ssh_date) do
        ssh = create :public_key, user: @free_user
        ssh.update!(accessed_at: last_ssh_date)
      end

      assert_equal last_ssh_date.in_time_zone, @free_user.last_active_timestamp
    end

    test "GHES only: returns date of the most recent active interaction" do
      int_user = create(:user, created_at: 1.week.ago)
      Interaction.track_active_session(int_user)

      assert_equal int_user.interaction.last_active_at, int_user.last_active_timestamp
    end if GitHub.enterprise?
  end

  test "non-duplicate logins don't read as duplicate" do
    user = create(:user)
    dupe = create(:user)
    assert !user.has_duplicate_login?
    assert_equal 0, user.duplicate_email_count
  end

  test "non-duplicate e-mails don't read as duplicate" do
    user = create(:user)
    dupe = create(:user)
    assert !user.has_duplicate_email?
    assert_equal 0, user.duplicate_email_count
  end

  test "duplicate email counts" do
    user = create(:user)
    dupe = create(:user)
    dupe.emails.first.update_attribute(:email, user.emails.first.email)

    assert user.has_duplicate_email?
    assert_equal 1, user.duplicate_email_count
  end
end
