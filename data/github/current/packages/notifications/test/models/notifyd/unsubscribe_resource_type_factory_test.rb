# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class UnsubscribeResourceTypeFactoryTest < GitHub::TestCase
    test "finds a standard resource" do
      resource = create(:gist)
      result = UnsubscribeResourceTypeFactory.build(klass: resource.class).fetch(id: resource.id)
      assert_equal resource, result
    end

    test "does not find a deleted standard resource" do
      resource = create(:gist)
      resource.destroy
      result = UnsubscribeResourceTypeFactory.build(klass: resource.class).fetch(id: resource.id)
      assert_nil result
    end

    test "finds a discussion" do
      resource = create(:discussion)
      result = UnsubscribeResourceTypeFactory.build(klass: resource.class).fetch(id: resource.id)
      assert_equal resource, result
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

      result = UnsubscribeResourceTypeFactory.build(klass: discussion.class).fetch(id: discussion.id)
      refute_equal discussion.id, result.id
      assert_equal discussion.title, result.title
    end

    test "does not find a deleted discussion" do
      resource = create(:discussion)
      resource.destroy
      result = UnsubscribeResourceTypeFactory.build(klass: resource.class).fetch(id: resource.id)
      assert_nil result
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

      assert_nil UnsubscribeResourceTypeFactory.build(klass: discussion.class).fetch(id: discussion.id)
    end

    test "finds an issue" do
      resource = create(:issue)
      result = UnsubscribeResourceTypeFactory.build(klass: resource.class).fetch(id: resource.id)
      assert_equal resource, result
    end

    test "finds a transfered issue" do
      user = create(:user)
      old_repository = create(:repository, owner: user)
      issue = create(:issue, repository: old_repository)
      new_repository = create(:repository, owner: user)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: old_repository, new_repository: new_repository, actor: user)
      transfer.transfer!
      transfer.save!

      result = UnsubscribeResourceTypeFactory.build(klass: issue.class).fetch(id: issue.id)
      assert_equal issue.title, result.title
      refute_equal issue.id, result.id
    end

    test "does not find a deleted issue" do
      resource = create(:issue)
      resource.destroy
      result = UnsubscribeResourceTypeFactory.build(klass: resource.class).fetch(id: resource.id)
      assert_nil result
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

      assert_nil UnsubscribeResourceTypeFactory.build(klass: issue.class).fetch(id: issue.id)
    end
  end
end
