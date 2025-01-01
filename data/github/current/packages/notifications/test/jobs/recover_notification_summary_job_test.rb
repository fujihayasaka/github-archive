# typed: true
# frozen_string_literal: true

require "test_helper"

class RecoverNotificationSummaryJobTest < GitHub::TestCase
  include CommitTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)
    @issue = create(:issue, user: @user, repository: @repo)
    @issue_comment = create(:issue_comment, issue: @issue, user: create(:user))
  end

  setup do
    @list = Newsies::List.to_object(@repo)
    @thread = Newsies::Thread.to_object(@issue)
  end

  context "when the reference is wrong" do
    test "#perform restores entries to the correct summary" do
      summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue_comment)
      Newsies::NotificationEntry.insert(@user.id, summary)
      Newsies::SavedNotificationEntry.save(user_id: @user.id, summary_id: summary.id, list: @list, thread: @thread)

      entry = Newsies::NotificationEntry.where(summary_id: summary.id).first
      saved_entry = Newsies::SavedNotificationEntry.where(summary_id: summary.id).first

      id = summary.id
      summary.delete

      new_summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue_comment)

      assert_nil NotificationSummary.find_by(id: id)

      RecoverNotificationSummaryJob.perform_now(
        id: id,
        list_type: @list.type,
        list_id: @list.id,
        thread_type: @thread.type,
        thread_id: @thread.id,
      )

      entry.reload
      assert_equal new_summary.id, entry.summary_id
      saved_entry.reload
      assert_equal new_summary.id, saved_entry.summary_id
    end
  end

  context "when the summary is missing" do
    test "#perform restores a missing summary" do
      summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue_comment)
      id = summary.id
      summary.delete

      assert_nil NotificationSummary.find_by(id: id)

      RecoverNotificationSummaryJob.perform_now(
        id: id,
        list_type: @list.type,
        list_id: @list.id,
        thread_type: @thread.type,
        thread_id: @thread.id,
      )

      refute_nil NotificationSummary.find_by(id: id)
    end

    test "#perform deletes unrecoverable entries" do
      GitHub.flipper[:notifications_summaries_delete_unrecoverable_entries].enable

      summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue_comment)
      Newsies::NotificationEntry.insert(@user.id, summary)
      Newsies::SavedNotificationEntry.save(user_id: @user.id, summary_id: summary.id, list: @list, thread: @thread)
      id = summary.id
      summary.delete

      assert_nil NotificationSummary.find_by(id: id)

      NotificationSummary.any_instance.expects(:rebuild_summary).raises(NoMethodError)

      RecoverNotificationSummaryJob.perform_now(
        id: id,
        list_type: @list.type,
        list_id: @list.id,
        thread_type: @thread.type,
        thread_id: @thread.id,
      )

      assert_nil NotificationSummary.find_by(id: id)
      assert_empty Newsies::NotificationEntry.where(summary_id: id)
      assert_empty Newsies::SavedNotificationEntry.where(summary_id: id)
    end

    test "#perform does not do anything with existing summary" do
      summary = NotificationSummary.fetch_and_update!(@repo, @issue, @issue_comment)
      id = summary.id

      refute_nil NotificationSummary.find_by(id: id)

      RecoverNotificationSummaryJob.perform_now(
        id: id,
        list_type: @list.type,
        list_id: @list.id,
        thread_type: @thread.type,
        thread_id: @thread.id,
      )

      refute_nil NotificationSummary.find_by(id: id)
    end

    test "#perform works with commits" do
      repo = create(:repository, owner: @user)
      commit = create_commit(repo: repo, user: @user)

      list = Newsies::List.to_object(repo)
      thread = Newsies::Thread.to_object(commit, list: list)

      summary = NotificationSummary.fetch_and_update!(repo, commit, commit)
      id = summary.id
      summary.delete

      assert_nil NotificationSummary.find_by(id: id)

      RecoverNotificationSummaryJob.perform_now(
        id: id,
        list_type: list.type,
        list_id: list.id,
        thread_type: thread.type,
        thread_id: thread.id,
      )

      refute_nil NotificationSummary.find_by(id: id)
    end
  end
end
