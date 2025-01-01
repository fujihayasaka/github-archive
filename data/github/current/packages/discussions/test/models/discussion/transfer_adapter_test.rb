# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTransferAdapterTest < GitHub::TestCase
  fixtures do
    @verified_user = create(:verified_user)

    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @public_discussion = travel_to(1.day.ago) do
      create(:discussion, :question, repository: @public_repo)
    end
    @other_repo = create(:private_repository, owner: @repo_owner, has_discussions: true)

    @org_admin = create(:verified_user)
    @org = create(:business_plus_organization, admin: @org_admin)
    @org_repo = create(:repository, owner: @org, has_discussions: true)

    @repo_triager = create(:verified_user)
    @org_repo.add_member(@repo_triager, action: :triage)

    @repo_maintainer = create(:verified_user)
    @org_repo.add_member(@repo_maintainer, action: :maintain)

    @repo_writer = create(:verified_user)
    @org_repo.add_member(@repo_writer, action: :write)

    @repo_admin = create(:verified_user)
    @org_repo.add_member(@repo_admin, action: :admin)

    @org_discussion = create(:discussion, repository: @org_repo)
  end

  context "#can_transfer_to?" do
    test "false when discussion is not able to be transferred" do
      Discussion.any_instance.stubs(:can_be_transferred?).returns(false)
      refute_valid_transfer(@public_discussion, new_repo: @other_repo, actor: @repo_owner)
    end

    test "true for a valid repo and actor" do
      assert_valid_transfer(@public_discussion, new_repo: @other_repo, actor: @repo_owner)
    end

    test "false when actor lacks write permission in new repository" do
      refute_valid_transfer(@public_discussion, new_repo: @other_repo,
        actor: @public_discussion.user)
    end

    test "false when new repository is archived" do
      @other_repo.set_archived
      refute_valid_transfer(@public_discussion, new_repo: @other_repo, actor: @repo_owner)
    end

    test "false when new repository does not have discussions turned on" do
      @other_repo.turn_off_discussions(actor: @repo_owner, instrument: false)
      refute_valid_transfer(@public_discussion, new_repo: @other_repo, actor: @repo_owner)
    end

    test "false when new repository has a different owner than current repo" do
      # Give the actor write permission so we know that's not the reason why it's
      # invalid; we want just the differing repo owner to be the thing stopping
      # the transfer:
      @org_repo.add_member(@repo_owner, action: :write)

      refute_valid_transfer(@public_discussion, new_repo: @org_repo, actor: @repo_owner)
    end

    test "false when current repository is private and new repo is public" do
      private_discussion = create(:discussion, repository: @other_repo)
      refute_predicate private_discussion, :public?,
        "need a discussion in a private repo for this test"
      refute_valid_transfer(private_discussion, new_repo: @public_repo, actor: @repo_owner)
    end
  end

  context "#can_be_transferred?" do
    test "false when repository is archived" do
      @public_repo.set_archived
      refute_predicate @public_discussion, :can_be_transferred?
    end

    test "false when repository has discussions turned off" do
      @public_repo.turn_off_discussions(actor: @repo_owner, instrument: false)
      refute_predicate @public_discussion, :can_be_transferred?
    end

    test "false when discussion is locked" do
      @public_discussion.lock(actor: @repo_owner)
      refute_predicate @public_discussion, :can_be_transferred?
    end

    test "false when discussion is in an error state" do
      @public_discussion.state = :error
      @public_discussion.error_reason = :close_failure
      refute_predicate @public_discussion, :can_be_transferred?
    end

    test "false when discussion is currently being transferred" do
      @public_discussion.state = :transferring
      refute_predicate @public_discussion, :can_be_transferred?
    end

    test "true for discussion that's open in a non-archived repo with discussions" do
      assert_predicate @public_discussion, :can_be_transferred?
    end

    test "true for closed discussion" do
      @public_discussion.close(actor: @repo_owner)
      assert_predicate @public_discussion, :can_be_transferred?
    end
  end

  context "#transferrable_by?" do
    test "false when discussion is not able to be transferred" do
      Discussion.any_instance.stubs(:can_be_transferred?).returns(false)
      refute @public_discussion.transferrable_by?(@public_discussion.user)
    end

    test "true for user who started discussion" do
      assert @public_discussion.transferrable_by?(@public_discussion.user)
    end

    test "true for repo owner" do
      assert @public_discussion.transferrable_by?(@repo_owner)
    end

    test "true for org admin in an org-owned repository" do
      assert @org_discussion.transferrable_by?(@org_admin)
    end

    test "true for repo admin" do
      assert @org_discussion.transferrable_by?(@repo_admin)
    end

    test "true for repo maintainer" do
      assert @org_discussion.transferrable_by?(@repo_maintainer)
    end

    test "false for anyone if modifiable_by_actor is overridden to false" do
      refute @org_discussion.transferrable_by?(@repo_admin, modifiable_by_actor: false)
    end

    test "false for user with repo triage access" do
      refute @org_discussion.transferrable_by?(@repo_triager)
    end

    test "true for user with repo write access" do
      assert @org_discussion.transferrable_by?(@repo_writer)
    end

    test "false when user-owned repository is archived" do
      @public_repo.set_archived
      refute @public_discussion.transferrable_by?(@public_discussion.user)
      refute @public_discussion.transferrable_by?(@repo_owner)
    end

    test "false when org-owned repository is archived" do
      @org_repo.set_archived
      refute @org_discussion.transferrable_by?(@org_discussion.user)
      refute @org_discussion.transferrable_by?(@org_admin)
      refute @org_discussion.transferrable_by?(@repo_admin)
      refute @org_discussion.transferrable_by?(@repo_maintainer)
      refute @org_discussion.transferrable_by?(@repo_writer)
      refute @org_discussion.transferrable_by?(@repo_triager)
    end

    test "false for anonymous user" do
      refute @public_discussion.transferrable_by?(nil)
    end

    test "true for anonymous user if modifiable_by_actor is overridden to true" do
      assert @public_discussion.transferrable_by?(nil, modifiable_by_actor: true)
    end

    if GitHub.email_verification_enabled?
      test "false for author without verified email address" do
        @public_discussion.user.emails.map(&:unverify!)
        refute @public_discussion.transferrable_by?(@public_discussion.user)
      end
    else
      test "true for author without verified email address" do
        @public_discussion.user.emails.map(&:unverify!)
        assert @public_discussion.transferrable_by?(@public_discussion.user)
      end
    end

    test "false for unrelated user" do
      refute @public_discussion.transferrable_by?(create(:verified_user))
    end
  end

  context "#async_possible_transfer_repositories" do
    test "includes all repos ordered by update time if discussion belongs to public repo" do
      user = create(:user)
      public_repo = create(:repository, owner: user, has_discussions: true)
      other_public_repo = create(:repository, owner: user, has_discussions: true)
      private_repo = create(:private_repository, owner: user, has_discussions: true)
      discussion = create(:discussion, repository: public_repo)

      travel_to(10.minutes.ago) { other_public_repo.touch }
      travel_to(5.minutes.ago) { private_repo.touch }

      results = discussion.async_possible_transfer_repositories(viewer: user).sync

      assert_equal [private_repo, other_public_repo], results
    end

    test "excludes repos that don't have discussions enabled" do
      user = create(:user)
      public_repo = create(:repository, owner: user, has_discussions: true)
      other_public_repo = create(:repository, owner: user, has_discussions: false)
      discussion = create(:discussion, repository: public_repo)

      results = discussion.async_possible_transfer_repositories(viewer: user).sync

      refute_includes results, other_public_repo
    end

    test "excludes repos that are deleted" do
      user = create(:user)
      public_repo = create(:repository, owner: user, has_discussions: true)
      remove_repo = create(:repository, owner: user, has_discussions: true)
      discussion = create(:discussion, repository: public_repo)

      remove_repo.remove(user, synchronous: true)
      results = discussion.async_possible_transfer_repositories(viewer: user).sync

      refute_includes results, remove_repo
    end

    test "only includes private repos if discussion belongs to private repo" do
      user = create(:user)
      private_repo = create(:private_repository, owner: user, has_discussions: true)
      other_private_repo = create(:private_repository, owner: user, has_discussions: true)
      public_repo = create(:repository, owner: user, has_discussions: true)
      discussion = create(:discussion, repository: private_repo)

      results = discussion.async_possible_transfer_repositories(viewer: user).sync

      assert_equal [other_private_repo], results
    end

    test "includes repos where the user has write access and above" do
      org = create(:organization)
      user = create(:user)
      repo = create(:repository, owner: org, has_discussions: true)
      admin_repo = create(:repository, owner: org, has_discussions: true)
      admin_repo.add_member(user, action: :admin)
      write_repo = create(:repository, owner: org, has_discussions: true)
      write_repo.add_member(user, action: :write)
      read_repo = create(:repository, owner: org, has_discussions: true)
      read_repo.add_member(user, action: :read)
      discussion = create(:discussion, repository: repo)

      travel_to(10.minutes.ago) { admin_repo.touch }
      travel_to(5.minutes.ago) { write_repo.touch }

      results = discussion.async_possible_transfer_repositories(viewer: user).sync

      assert_equal [write_repo, admin_repo], results
    end

    test "only includes repositories with at least 1 category that supports polls if discussion contains poll" do
      user = create(:user)
      category_poll = create(:discussion_category, supports_polls: true)
      category_no_poll = create(:discussion_category, supports_polls: false)
      repo1 = create(:repository, owner: user, has_discussions: true)
      repo2 = create(:repository, owner: user, has_discussions: true, discussion_categories: [category_poll])
      repo_no_polls_category = create(:repository, owner: user, has_discussions: true, discussion_categories: [category_no_poll])

      poll_category = repo1.discussion_categories.find_by(name: "Polls")
      poll = create(:discussion_poll, question: "What is your favorite pie?")
      discussion = create(:discussion, repository: repo1, category: poll_category, poll: poll)

      results = discussion.async_possible_transfer_repositories(viewer: user).sync
      refute_includes results, repo_no_polls_category
      assert_equal results, [repo2]
    end
  end

  def assert_valid_transfer(discussion, new_repo:, actor:)
    assert discussion.can_transfer_to?(new_repo, actor: actor),
      "expected #can_transfer_to? to be true for #{new_repo.nwo} as #{actor}"

    transfer = build(:discussion_transfer, old_discussion: discussion,
      new_repository: new_repo, actor: actor)
    assert_predicate transfer, :valid?,
      "should be able to build a valid discussion transfer when #can_transfer_to? is true"
  end

  def refute_valid_transfer(discussion, new_repo:, actor:)
    refute discussion.can_transfer_to?(new_repo, actor: actor),
      "expected #can_transfer_to? to be false for #{new_repo.nwo} as #{actor}"

    transfer = build(:discussion_transfer, old_discussion: discussion,
      new_repository: new_repo, actor: actor)
    refute_predicate transfer, :valid?,
      "should not be able to build a valid discussion transfer when #can_transfer_to? is false"
  end
end
