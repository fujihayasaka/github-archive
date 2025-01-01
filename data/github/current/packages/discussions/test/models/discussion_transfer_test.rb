# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTransferTest < GitHub::TestCase
  fixtures do
    User.create_ghost
    @owner = create(:verified_user)
    @member = create(:verified_user)
    @org = create(:organization)
    @org.add_member(@owner, action: :admin)
    @org.add_member(@member, action: :write)
    @old_repository = create(:repository, owner: @org, has_discussions: true)
    @new_repository = create(:repository, owner: @org, has_discussions: true)
    @discussion = create(:discussion, title: "Transfer me", user: @member,
      repository: @old_repository)
    @new_discussion = create(:discussion, repository: @new_repository,
      title: @discussion.title, user: @member)
  end

  context "validations" do
    test "requires actor" do
      transfer = DiscussionTransfer.new
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:actor], "must exist"
    end

    test "requires old discussion" do
      transfer = DiscussionTransfer.new
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion], "must exist"
    end

    test "requires old discussion number" do
      transfer = DiscussionTransfer.new
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion_number], "can't be blank"
    end

    test "requires old repository" do
      transfer = DiscussionTransfer.new
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_repository], "must exist"
    end

    test "requires new discussion" do
      transfer = DiscussionTransfer.new
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:new_discussion], "must exist"
    end

    test "requires new repository" do
      transfer = DiscussionTransfer.new
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:new_repository], "must exist"
    end

    test "requires a valid reason" do
      transfer = DiscussionTransfer.new(reason: "o noes")
      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:reason], "is not included in the list"
    end

    test "allows actor who has admin access to both repositories" do
      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner,
        new_discussion: @new_discussion)
      assert_predicate transfer, :valid?
    end

    test "allows actor who has write access to both repositories" do
      @old_repository.add_member(@member, action: :write)
      @new_repository.add_member(@member, action: :write)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @member,
        new_discussion: @new_discussion)
      assert_predicate transfer, :valid?
    end

    test "allows closed discussion" do
      @discussion.close(actor: @owner)
      @new_discussion.close(actor: @owner)

      transfer = DiscussionTransfer.new(
        old_discussion: @discussion,
        old_repository: @old_repository,
        new_repository: @new_repository,
        new_discussion: @new_discussion,
        actor: @owner,
      )
      assert_predicate transfer, :valid?
    end

    test "disallows old repo to be private when new repo is public" do
      private_repository = create(:private_repository, owner: @org, has_discussions: true)
      discussion = create(
        :discussion,
        title: "you can't transfer me",
        user: @member,
        repository: private_repository,
      )

      transfer = DiscussionTransfer.new(old_discussion: discussion,
        old_repository: private_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion],
        "cannot be transferred from a private repository to a public repository"
    end

    test "disallows actor who lacks write access to old repository" do
      rando = create(:user)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: rando)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:actor],
        "must have write permission on current repository"
    end

    test "disallows actor who lacks write access to new repository" do
      rando = create(:user)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: rando)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:actor],
        "must have write permission on new repository"
    end

    test "disallows new repository to be in a different organization than the old repo" do
      other_org = create(:organization)
      new_repository = create(:repository, owner: other_org)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:new_repository],
        "must have the same owner as the current repository"
    end

    test "disallows locked old discussion" do
      @discussion.lock(actor: @owner)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion],
        "cannot be locked, being transferred, or in an error state"
    end

    test "disallows old discussion that is already being transferred" do
      @discussion.update!(state: :transferring)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion],
        "cannot be locked, being transferred, or in an error state"
    end

    test "disallows old discussion that is being converted from an issue" do
      issue = create(:issue, repository: @old_repository)
      @discussion.update!(state: :converting, issue_id: issue.id)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion],
        "cannot be locked, being transferred, or in an error state"
    end

    test "disallows old discussion that is in an error state" do
      @discussion.update!(state: :error, error_reason: :close_failure)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_discussion],
        "cannot be locked, being transferred, or in an error state"
    end

    test "disallows archived old repository" do
      @old_repository.update(maintained: false)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_repository],
        "must not be archived"
    end

    test "disallows archived new repository" do
      @new_repository.update(maintained: false)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:new_repository],
        "must not be archived"
    end

    test "disallows old repository with discussions disabled" do
      @old_repository.turn_off_discussions(actor: @owner, instrument: false)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:old_repository],
        "must have discussions enabled"
    end

    test "disallows new repository with discussions disabled" do
      @new_repository.turn_off_discussions(actor: @owner, instrument: false)

      transfer = DiscussionTransfer.new(old_discussion: @discussion,
        old_repository: @old_repository, new_repository: @new_repository, actor: @owner)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:new_repository],
        "must have discussions enabled"
    end
  end

  context ".find_from" do
    test "returns nil when there's no transfer" do
      transfer, transfer_exists = DiscussionTransfer.find_from(repository: create(:repository), number: "123")
      assert_nil transfer
      assert_equal false, transfer_exists
    end

    test "finds the discussion_transfer when there's one redirect" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      # Delete the original discussion to simulate completing the transfer
      transfer.old_discussion.destroy!

      result, transfer_exists = DiscussionTransfer.find_from(repository: @old_repository,
        number: @discussion.number)
      assert_equal transfer, result
      assert_equal true, transfer_exists
    end

    test "finds the discussion_transfer when there's two redirects" do
      first_transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      # Delete the original discussion to simulate completing the transfer
      first_transfer.old_discussion.destroy!

      second_transfer = create(:discussion_transfer, old_discussion: first_transfer.new_discussion,
        new_repository: create(:repository, owner: @org, has_discussions: true), actor: @owner)

      # Delete the first transferred discussion to simulate completing the transfer
      second_transfer.old_discussion.destroy!

      result, transfer_exists = DiscussionTransfer.find_from(repository: @old_repository, number: @discussion.number)
      assert_equal second_transfer, result
      assert_equal true, transfer_exists
    end

    test "returns nil when number of redirects exceeds number of transfers" do
      first_transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      # Delete the original discussion to simulate completing the transfer
      first_transfer.old_discussion.destroy!

      second_transfer = create(:discussion_transfer, old_discussion: first_transfer.new_discussion,
        new_repository: create(:repository, owner: @org, has_discussions: true), actor: @owner)

      # Delete the first transferred discussion to simulate completing the transfer
      second_transfer.old_discussion.destroy!

      DiscussionTransfer.stub_const(:DEFAULT_TRANSFER_TRAVERSAL_DEPTH, 1) do
        result, transfer_exists = DiscussionTransfer.find_from(repository: @old_repository, number: @discussion.number)
        assert_nil result
        assert_equal true, transfer_exists
      end
    end
  end

  context ".find_new_id_by_original_id" do
    test "returns nil when there's no transfer" do
      transfer = DiscussionTransfer.find_new_id_by_original_id(original_id: create(:discussion).id)
      assert_nil transfer
    end

    test "finds the discussion_transfer when there's one redirect" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      # Delete the original discussion to simulate completing the transfer
      transfer.old_discussion.destroy!

      result = DiscussionTransfer.find_new_id_by_original_id(original_id: @discussion.id)
      assert_equal transfer.new_discussion_id, result
    end

    test "finds the discussion_transfer when there's two redirects" do
      first_transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      # Delete the original discussion to simulate completing the transfer
      first_transfer.old_discussion.destroy!

      second_transfer = create(:discussion_transfer, old_discussion: first_transfer.new_discussion,
        new_repository: create(:repository, owner: @org, has_discussions: true), actor: @owner)

      # Delete the first transferred discussion to simulate completing the transfer
      second_transfer.old_discussion.destroy!

      result = DiscussionTransfer.find_new_id_by_original_id(original_id: @discussion.id)
      assert_equal second_transfer.new_discussion_id, result
    end

    test "returns nil when number of redirects exceeds number of transfers" do
      first_transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      # Delete the original discussion to simulate completing the transfer
      first_transfer.old_discussion.destroy!

      second_transfer = create(:discussion_transfer, old_discussion: first_transfer.new_discussion,
        new_repository: create(:repository, owner: @org, has_discussions: true), actor: @owner)

      # Delete the first transferred discussion to simulate completing the transfer
      second_transfer.old_discussion.destroy!

      DiscussionTransfer.stub_const(:DEFAULT_TRANSFER_TRAVERSAL_DEPTH, 1) do
        assert_nil DiscussionTransfer.find_new_id_by_original_id(original_id: @discussion.id)
      end
    end
  end
end
