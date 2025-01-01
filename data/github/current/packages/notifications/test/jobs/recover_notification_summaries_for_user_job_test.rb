# typed: true
# frozen_string_literal: true

require "test_helper"

class RecoverNotificationSummariesForUserJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)

    @issue_a = create(:issue, user: @user, repository: @repo)
    @issue_comment_a = create(:issue_comment, issue: @issue, user: create(:user))

    @issue_b = create(:issue, user: @user, repository: @repo)
    @issue_comment_b = create(:issue_comment, issue: @issue, user: create(:user))

    @issue_c = create(:issue, user: @user, repository: @repo)
    @issue_comment_c = create(:issue_comment, issue: @issue, user: create(:user))

    @summary_a = NotificationSummary.fetch_and_update!(@repo, @issue_a, @issue_comment_a)
    Newsies::NotificationEntry.insert(@user.id, @summary_a)
    @summary_b = NotificationSummary.fetch_and_update!(@repo, @issue_b, @issue_comment_b)
    Newsies::NotificationEntry.insert(@user.id, @summary_b)
    @summary_c = NotificationSummary.fetch_and_update!(@repo, @issue_c, @issue_comment_c)
    Newsies::SavedNotificationEntry.save(
      user_id: @user.id,
      summary_id: @summary_c.id,
      list: Newsies::List.to_object(@repo),
      thread: Newsies::Thread.to_object(@issue_c)
    )

    @ids = [@summary_a, @summary_b, @summary_c].map(&:id)
  end

  setup do
    @summary_b.delete
    @summary_c.delete

    @list = Newsies::List.to_object(@repo)
    @threads = [@issue_a, @issue_b, @issue_c].map do |issue|
      Newsies::Thread.to_object(issue)
    end

    @entries = Newsies::NotificationEntry.for_user(@user.id).order(:id).to_a
    @saved_entries = Newsies::SavedNotificationEntry.for_user(@user.id).order(:id).to_a
  end

  test "#perform enqueues jobs to recover summaries for broken entries" do
    RecoverNotificationSummaryJob.expects(:perform_later).with(
      id: @ids[1],
      list_id: @list.id,
      list_type: @list.type,
      thread_id: @threads[1].id.to_s,
      thread_type: @threads[1].type,
    )

    RecoverNotificationSummaryJob.expects(:perform_later).with(
      id: @ids[2],
      list_id: @list.id,
      list_type: @list.type,
      thread_id: @threads[2].id.to_s,
      thread_type: @threads[2].type,
    )

    RecoverNotificationSummariesForUserJob.perform_now(user_id: @user.id)
  end

  test "#perform continues from a given NotificationEntry ID" do
    RecoverNotificationSummaryJob.expects(:perform_later).with(
      id: @ids[1],
      list_id: @list.id,
      list_type: @list.type,
      thread_id: @threads[1].id.to_s,
      thread_type: @threads[1].type,
    )

    RecoverNotificationSummaryJob.expects(:perform_later).with(
      id: @ids[2],
      list_id: @list.id,
      list_type: @list.type,
      thread_id: @threads[2].id.to_s,
      thread_type: @threads[2].type,
    )

    RecoverNotificationSummariesForUserJob.perform_now(
      user_id: @user.id,
      start_id: @entries.last.id,
      start_type: "Newsies::NotificationEntry",
    )
  end

  test "#perform continues from a given SavedNotificationEntry ID" do
    RecoverNotificationSummaryJob.expects(:perform_later).with(
      id: @ids[2],
      list_id: @list.id,
      list_type: @list.type,
      thread_id: @threads[2].id.to_s,
      thread_type: @threads[2].type,
    )

    RecoverNotificationSummariesForUserJob.perform_now(
      user_id: @user.id,
      start_id: @saved_entries.first.id,
      start_type: "Newsies::SavedNotificationEntry",
    )
  end

  test "#perform enqueues a follow up job if timer is up" do
    GitHub::SafeTimer.any_instance.stubs(:expired?).returns(false, true)

    RecoverNotificationSummariesForUserJob.perform_now(
      user_id: @user.id,
      start_id: @entries.first.id,
      start_type: "Newsies::NotificationEntry",
    )

    RecoverNotificationSummariesForUserJob.perform_now(user_id: @user.id)
  end

  test "#perform enqueues a follow up job with saved entries if timer is up" do
    GitHub::SafeTimer.any_instance.stubs(:expired?).returns(false, false, true)

    RecoverNotificationSummariesForUserJob.perform_now(
      user_id: @user.id,
      start_id: @saved_entries.first.id,
      start_type: "Newsies::SavedNotificationEntry",
    )

    RecoverNotificationSummariesForUserJob.perform_now(user_id: @user.id)
  end
end
