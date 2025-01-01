# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class UnsubscribeResourceTypeFactoryTest < GitHub::TestCase
    test "finds a standard resource" do
      resource = create(:gist)
      NotificationSummary.new(list: resource.notifications_list, thread: resource.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(resource).key)
      assert_equal resource, result.thread
    end

    test "does not find a deleted standard resource" do
      resource = create(:gist)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      resource.destroy
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(resource).key)
      assert_nil result.thread
    end

    test "finds a standard resource without thread key" do
      resource = create(:gist)
      NotificationSummary.new(list: resource.notifications_list, thread: resource.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_equal resource, result.thread
    end

    test "does not find a deleted standard resource without thread key" do
      resource = create(:gist)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      resource.destroy
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_nil result.thread
    end

    test "finds a discussion" do
      resource = create(:discussion)
      NotificationSummary.new(list: resource.notifications_list, thread: resource.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(resource).key)
      assert_equal resource, result.thread
    end

    test "finds a discussion without thread key" do
      resource = create(:discussion)
      NotificationSummary.new(list: resource.notifications_list, thread: resource.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_equal resource, result.thread
    end

    test "finds a transfered discussion" do
      owner = create(:verified_user)
      org = create(:organization, admin: owner)
      old_repository = create(:repository, owner: org, has_discussions: true)
      new_repository = create(:repository, owner: org, has_discussions: true)
      discussion = create(:discussion, title: "Transfer me", user: owner, repository: old_repository)

      transferrer = DiscussionRepositoryTransferrer
        .for_new_transfer(discussion, new_repository: new_repository, actor: owner)
      transferrer.start_transfer
      transferrer.complete_transfer

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(discussion.notifications_list, discussion.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(discussion).key)
      assert_equal discussion.title, result.thread.title
      refute_equal discussion.id, result.thread.id
    end

    test "does not find a deleted discussion" do
      resource = create(:discussion)
      resource.destroy
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(resource).key)
      assert_nil result.thread
    end

    test "does not find a deleted discussion without thread key" do
      resource = create(:discussion)
      resource.destroy
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_nil result.thread
    end

    test "does not find a deleted transfered discussion" do
      owner = create(:verified_user)
      org = create(:organization, admin: owner)
      old_repository = create(:repository, owner: org, has_discussions: true)
      new_repository = create(:repository, owner: org, has_discussions: true)
      discussion = create(:discussion, title: "Transfer me", user: owner, repository: old_repository)

      transferrer = DiscussionRepositoryTransferrer
        .for_new_transfer(discussion, new_repository: new_repository, actor: owner)
      transferrer.start_transfer
      transferrer.complete_transfer

      transferrer.new_discussion.destroy!

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(discussion.notifications_list, discussion.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(discussion).key)
      assert_nil result.thread
    end

    test "does not find a deleted transfered discussion without thread key" do
      owner = create(:verified_user)
      org = create(:organization, admin: owner)
      old_repository = create(:repository, owner: org, has_discussions: true)
      new_repository = create(:repository, owner: org, has_discussions: true)
      discussion = create(:discussion, title: "Transfer me", user: owner, repository: old_repository)

      transferrer = DiscussionRepositoryTransferrer
        .for_new_transfer(discussion, new_repository: new_repository, actor: owner)
      transferrer.start_transfer
      transferrer.complete_transfer

      transferrer.new_discussion.destroy!

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(discussion.notifications_list, discussion.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_nil result.thread
    end

    test "finds an issue" do
      resource = create(:issue)
      NotificationSummary.new(list: resource.notifications_list, thread: resource.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(resource).key)
      assert_equal resource, result.thread
    end

    test "finds an issue without thread key" do
      resource = create(:issue)
      NotificationSummary.new(list: resource.notifications_list, thread: resource.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_equal resource, result.thread
    end

    test "finds a transfered issue" do
      user = create(:user)
      old_repository = create(:repository, owner: user)
      issue = create(:issue, repository: old_repository)
      new_repository = create(:repository, owner: user)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: old_repository, new_repository: new_repository, actor: user)
      transfer.transfer!
      transfer.save!

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(issue.notifications_list, issue.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(issue).key)
      assert_equal issue.title, result.thread.title
      refute_equal issue.id, result.thread.id
    end

    test "does not find a deleted issue" do
      resource = create(:issue)
      resource.destroy

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(resource).key)
      assert_nil result.thread
    end

    test "does not find a deleted issue without thread key" do
      resource = create(:issue)
      resource.destroy

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(resource.notifications_list, resource.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)
      assert_nil result.thread
    end

    test "does not find a deleted transfered issue" do
      user = create(:user)
      old_repository = create(:repository, owner: user)
      issue = create(:issue, repository: old_repository)

      new_repository = create(:repository, owner: user)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: old_repository, new_repository: new_repository, actor: user)
      transfer.transfer!
      transfer.save!

      Issue.find(transfer.new_issue_id).destroy!

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(issue.notifications_list, issue.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(issue).key)

      assert_nil result.thread
    end

    test "does not find a deleted transfered issue without thread key" do
      user = create(:user)
      old_repository = create(:repository, owner: user)
      issue = create(:issue, repository: old_repository)

      new_repository = create(:repository, owner: user)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: old_repository, new_repository: new_repository, actor: user)
      transfer.transfer!
      transfer.save!

      Issue.find(transfer.new_issue_id).destroy!

      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(issue.notifications_list, issue.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: nil)

      assert_nil result.thread
    end

    test "finds a git commit resource" do
      repository = create(:repository, from_example: :simple)
      commit = create(:commit, repository: repository, create_branch: false)
      NotificationSummary.new(list: commit.notifications_list, thread: commit.notifications_thread).summarize!(nil)
      rollup = GitHub.newsies.web.find_rollup_summary_by_thread(commit.notifications_list, commit.notifications_thread)
      result = UnsubscribeResourceTypeFactory.build(rollup_summary_result: rollup, thread_key: Newsies::Thread.to_object(commit).key)
      assert_equal commit, result.thread
    end

  end
end
