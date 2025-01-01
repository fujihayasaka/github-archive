# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionRepositoryTransferrerTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @owner = create(:verified_user)
    @member = create(:verified_user)
    @org = create(:organization)
    @org.add_member(@owner, action: :admin)
    @org.add_member(@member, action: :write)
    @old_repository = create(:repository, owner: @org, has_discussions: true)
    @old_category = create(:discussion_category, repository: @old_repository, supports_mark_as_answer: true)
    @new_repository = create(:private_repository, owner: @org, has_discussions: true)
    @new_category = create(:discussion_category, repository: @new_repository,
      name: @old_category.name)
    @discussion = create(:discussion, title: "Transfer me", user: @member,
      repository: @old_repository, category: @old_category)
  end

  context "#start_transfer" do
    test "creates new discussion and new transfer" do
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion, actor: @owner,
        new_repository: @new_repository)

      assert transferrer.start_transfer

      refute_nil transferrer.discussion_transfer
      assert_predicate transferrer.discussion_transfer, :started?

      refute_nil transferrer.new_discussion
      assert_equal @new_repository, transferrer.new_discussion.repository
      assert_equal @discussion.user, transferrer.new_discussion.user
      assert_equal @discussion.title, transferrer.new_discussion.title
    end

    test "transfers the created_at" do
      t = 1.week.ago
      @discussion.update_column(:created_at, t)
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer

      refute_nil transferrer.new_discussion
      assert_equal @discussion.user, transferrer.new_discussion.user
      assert_equal t.to_i, transferrer.new_discussion.created_at.to_i
    end

    test "transfers bumped_at" do
      bumped_at = 1.week.ago
      @discussion.update_column(:bumped_at, bumped_at)
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer

      refute_nil transferrer.new_discussion
      assert_equal @discussion.user, transferrer.new_discussion.user
      assert_equal bumped_at.to_i, transferrer.new_discussion.bumped_at.to_i
    end

    test "transfers the category when category of same name and type exists in new repo" do
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer

      refute_nil transferrer.new_discussion
      assert_equal @new_category, transferrer.new_discussion.category
    end

    test "returns error if no category with the same type exists in the new repo" do
      @old_category.update!(name: "Pizza")
      @new_category.update!(name: "Pizza", supports_mark_as_answer: false)
      @new_repository.discussion_categories.where(supports_mark_as_answer: true).destroy_all

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      refute transferrer.start_transfer
      expected = "Unable to transfer discussion to #{@new_repository.name_with_owner} because the repository " \
        "does not have any discussion categories that support answers."
      assert_equal expected, transferrer.error
    end

    test "transfers to the same category type when no category of the same name exists in new repo" do
      unmatched_category = create(:discussion_category, repository: @old_repository, supports_mark_as_answer: true)
      @discussion.update!(category: unmatched_category)

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      assert_equal @new_repository.discussion_categories.find_by(supports_mark_as_answer: true),
        transferrer.new_discussion.category
    end

    test "returns error if repository does not have category that supports discussion or have general category" do
      @new_repository.discussion_categories.where(supports_mark_as_answer: true).destroy_all
      @new_repository.discussion_categories.where(
        supports_mark_as_answer: false,
        supports_polls: false,
        supports_announcements: false
      ).destroy_all

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      refute transferrer.start_transfer
      expected = "Unable to transfer discussion to #{@new_repository.name_with_owner} because the repository " \
        "does not have any discussion categories that support answers."
      assert_equal expected, transferrer.error
    end

    test "transfers the chosen answer" do
      answer = create(:discussion_comment, discussion: @discussion)
      @discussion.update_column(:chosen_comment_id, answer.id)
      transferrer = DiscussionRepositoryTransferrer.new(discussion: @discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer

      refute_nil transferrer.new_discussion
      assert_equal answer, transferrer.new_discussion.chosen_comment
    end

    test "transfers the poll" do
      @viewer = create(:user)
      poll_category = @old_repository.discussion_categories.find_by(name: "Polls")
      poll = create(:discussion_poll, question: "What is your favorite pie?")
      options = [
        create(:discussion_poll_option, poll: poll, option: "Pumpkin"),
        create(:discussion_poll_option, poll: poll, option: "Sweet Potato"),
        create(:discussion_poll_option, poll: poll, option: "Apple Potato")
      ]
      poll.options = options

      vote = create(:discussion_poll_vote, poll: poll, option: options.first, user: @viewer)
      create(:discussion_poll_vote, poll: poll, option: options.last, user: create(:user))
      create(:discussion_poll_vote, poll: poll, option: options.last, user: create(:user))
      create(:discussion_poll_vote, poll: poll, option: options.last, user: create(:user))

      discussion_with_poll = create(:discussion, title: "Transfer me", user: @member,
        repository: @old_repository, category: poll_category, poll: poll)

      transferrer = DiscussionRepositoryTransferrer.new(discussion: discussion_with_poll,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer

      refute_nil transferrer.new_discussion.poll
      refute_nil transferrer.new_discussion.poll.options
      assert_equal poll.question, transferrer.new_discussion.poll.question
      assert_equal poll.options[0].option, transferrer.new_discussion.poll.options[0].option
    end

    test "transfers discussion when polls category with different name exists in new repo" do
      discussion = create(:discussion, :with_poll, repository: @old_repository)
      new_category = @new_repository.discussion_categories.find_by(supports_polls: true)
      new_category.update!(name: "Dahyun")

      transferrer = DiscussionRepositoryTransferrer.new(
        discussion: discussion,
        new_repository: @new_repository,
        actor: @owner
      )

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion.poll
      assert_equal "Dahyun", transferrer.new_discussion.category.name
    end

    test "transfers discussion to available polls category when category with same name does not exist in new repo" do
      discussion = create(:discussion, :with_poll, repository: @old_repository)
      discussion.category.update!(name: "Stan Twice")
      new_category = @new_repository.discussion_categories.find_by(supports_polls: true)

      transferrer = DiscussionRepositoryTransferrer.new(
        discussion: discussion,
        new_repository: @new_repository,
        actor: @owner
      )

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion.poll
      assert_equal "Polls", transferrer.new_discussion.category.name
    end

    test "errors if new repo is not accessible by actor" do
      discussion = create(:discussion, :with_poll, repository: @old_repository)
      private_repo = create(:private_repository, has_discussions: true)

      transferrer = DiscussionRepositoryTransferrer.new(
        discussion: discussion,
        new_repository: private_repo,
        actor: @owner,
      )

      refute transferrer.start_transfer
      expected = "That repository is not a valid destination for this discussion."
      assert_equal expected, transferrer.error
    end

    test "errors if new repo does not contain any poll categories" do
      discussion = create(:discussion, :with_poll, repository: @old_repository)
      @new_repository.discussion_categories.where(supports_polls: true).destroy_all

      transferrer = DiscussionRepositoryTransferrer.new(
        discussion: discussion,
        new_repository: @new_repository,
        actor: @owner
      )

      refute transferrer.start_transfer
      expected = "Unable to transfer discussion to #{@new_repository.nwo} because the repository does not have any " \
                 "discussion categories that support polls."
      assert_equal expected, transferrer.error
    end

    test "returns false when discussion does not save" do
      Discussion.any_instance.stubs(:save).returns(false)
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      refute transferrer.start_transfer
      refute_nil transferrer.error
    end

    test "returns false when transfer record does not save" do
      DiscussionTransfer.any_instance.stubs(:save).returns(false)
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      refute transferrer.start_transfer
      refute_nil transferrer.error
    end

    test "allows discussion to be transferred even if author was blocked" do
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member(@member)
      end
      @org.block(@member)
      assert @member.blocked_by?(@org), "Member should be blocked from org"

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      assert_equal @discussion.user, transferrer.new_discussion.user
    end

    test "converts bare references in body to global references" do
      referenced_discussion = create(:discussion, title: "I'm staying put",
        user: @member, repository: @old_repository)
      @discussion.update!(body: "This is related to ##{referenced_discussion.number}")

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      expected = "This is related to #{@old_repository.nwo}##{referenced_discussion.number}"
      assert_equal expected, transferrer.new_discussion.body
    end

    test "converts bare references at start of line in body to global references" do
      referenced_discussion = create(:discussion, title: "I'm staying put", user: @member,
        repository: @old_repository)
      @discussion.update!(body: "##{referenced_discussion.number}")

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      assert_equal [@old_repository.nwo, "#", referenced_discussion.number].join,
        transferrer.new_discussion.body
    end

    test "converts bare references in body to global references when referenced record was transferred already" do
      referenced_discussion = create(:discussion, title: "I'm going to be transferred first",
        user: @member, repository: @old_repository)
      @discussion.update!(body: "This is related to ##{referenced_discussion.number}")

      # first, transfer the referenced discussion
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(referenced_discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      assert transferrer.complete_transfer
      transferred_discussion = transferrer.new_discussion

      # then, transfer the discussion that references it
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      expected = "This is related to #{@new_repository.name_with_owner}##{transferred_discussion.number}"
      assert_equal expected, transferrer.new_discussion.body
    end

    test "does not convert bare reference if referenced record does not exist" do
      non_existent_discussion_num = @old_repository.discussions.maximum(:number) + 1000
      assert_empty @old_repository.discussions.where(number: non_existent_discussion_num)

      @discussion.update!(body: "This is related to ##{non_existent_discussion_num}")

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      assert_equal transferrer.new_discussion.body, @discussion.body
    end

    test "does not convert global references in body" do
      unrelated_repo = create(:repository, owner: @org, has_discussions: true)
      referenced_discussion = create(:discussion, title: "I'm staying put", user: @member,
        repository: unrelated_repo)
      referenced_discussion_text = [unrelated_repo.nwo, "#", referenced_discussion.number].join
      @discussion.update!(body: "This is related to #{referenced_discussion_text}")

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      assert_equal transferrer.new_discussion.body, @discussion.body
    end

    test "does not convert non-reference text to a reference" do
      referenced_discussion = create(:discussion, title: "I'm staying put", user: @member,
        repository: @old_repository)
      # these are not discussion references because there is a space or incorrect number of #s
      @discussion.update!(body: "This problem has occurred # #{referenced_discussion.number} " \
        "times in production and I have ####{referenced_discussion.number} thoughts!")

      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      refute_nil transferrer.new_discussion
      assert_equal transferrer.new_discussion.body, @discussion.body
    end
  end

  context "#revert_started_transfer" do
    test "returns false when given an unsaved transfer record" do
      transfer = build(:discussion_transfer)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      refute transferrer.revert_started_transfer
      assert_equal "Cannot revert a transfer that has not started.", transferrer.error
    end

    test "returns false when given a finished transfer record" do
      transfer = create(:discussion_transfer, :done)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      refute transferrer.revert_started_transfer
      assert_equal "Cannot revert a transfer that has already finished.", transferrer.error
    end

    test "deletes new discussion when old discussion still exists" do
      transfer = create(:discussion_transfer)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert_difference("Discussion.count", -1) do
        assert transferrer.revert_started_transfer
      end

      assert Discussion.exists?(transfer.old_discussion_id)
      refute Discussion.exists?(transfer.new_discussion_id)
    end

    test "deletes transfer record when old discussion still exists" do
      transfer = create(:discussion_transfer)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert_difference("DiscussionTransfer.count", -1) do
        assert transferrer.revert_started_transfer
      end

      refute DiscussionTransfer.exists?(transfer.id)
    end

    test "does not delete new discussion or transfer record when old discussion is gone" do
      transfer = create(:discussion_transfer)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)
      transfer.old_discussion.delete

      assert_no_difference(["DiscussionTransfer.count", "Discussion.count"]) do
        refute transferrer.revert_started_transfer
      end

      assert_equal "Cannot revert a transfer where discussion in old repository has " \
        "already been deleted.", transferrer.error
      assert DiscussionTransfer.exists?(transfer.id)
      assert Discussion.exists?(transfer.new_discussion_id)
    end
  end

  context "#complete_transfer" do
    test "returns false when transfer event doesn't save" do
      DiscussionEvent.any_instance.stubs(:save).returns(false)
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      refute transferrer.complete_transfer
      refute_nil transferrer.error
      assert_predicate transferrer.discussion_transfer, :errored?
    end

    test "returns false when new discussion doesn't save" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)
      Discussion.any_instance.stubs(:save).returns(false)

      refute transferrer.complete_transfer
      refute_nil transferrer.error
      assert_predicate transferrer.discussion_transfer, :errored?
    end

    test "returns false when old discussion isn't deleted" do
      Discussion.any_instance.stubs(:destroy).returns(false)
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      refute transferrer.complete_transfer
      refute_nil transferrer.error
      assert_predicate transferrer.discussion_transfer, :errored?
    end

    test "returns false when transfer record doesn't save" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)
      DiscussionTransfer.any_instance.stubs(:save).returns(false)

      refute transferrer.complete_transfer
      refute_nil transferrer.error
    end

    test "transfers reactions" do
      reaction = create(:discussion_reaction, user: @owner, discussion: @discussion)
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert transferrer.complete_transfer
      assert_equal reaction.reload.discussion, transferrer.new_discussion
    end

    test "reparents discussion events" do
      event = create(:discussion_event, discussion: @discussion)
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert transferrer.complete_transfer
      refute_nil transferrer.new_discussion
      assert_equal transferrer.new_discussion, event.reload.discussion
      assert_equal @new_repository, event.repository
    end

    test "reparents comments" do
      comment = create(:discussion_comment, discussion: @discussion)
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert transferrer.complete_transfer
      refute_nil transferrer.new_discussion
      assert_equal transferrer.new_discussion, comment.reload.discussion
      assert_equal @new_repository, comment.repository
    end

    test "copies subscribers from old discussion" do
      subscriber = create(:user)
      @new_repository.add_member(subscriber)
      @discussion.subscribe(subscriber, "manual")

      ignoring_subscriber = create(:user)
      @new_repository.add_member(ignoring_subscriber)
      @discussion.subscribe(ignoring_subscriber, "manual")
      @discussion.unsubscribe(ignoring_subscriber)

      assert @discussion.subscribed?(subscriber),
        "need subscriber subscribed to discussion for this test"
      refute @discussion.subscribed?(ignoring_subscriber),
        "need ignoring_subscriber not subscribed to discussion for this test"

      transfer = create(:discussion_transfer, old_discussion: @discussion.reload,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      perform_enqueued_jobs(only: [Newsies::CopyThreadSubscribersJob]) do
        assert transferrer.complete_transfer
      end

      new_discussion = transferrer.new_discussion
      refute_nil new_discussion
      assert new_discussion.subscribed?(subscriber),
        "expected subscriber to be subscribed to the new discussion"
      refute new_discussion.subscribed?(ignoring_subscriber),
        "expected ignoring_subscriber to not be subscribed to the new discussion"
      refute_predicate new_discussion.subscription_status(ignoring_subscriber),
        :valid?, "expected ignoring_subscriber to be unsubscribed from new discussion"
    end

    test "creates a 'transferred' event on the new discussion" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert_difference("DiscussionEvent.transferred.count") do
        assert transferrer.complete_transfer
      end

      refute_nil transferrer.new_discussion
      transfer_event = transferrer.new_discussion.events.transferred.first
      refute_nil transfer_event
      assert_equal transfer_event, transfer.new_discussion_event
      assert_equal transfer, transfer_event.discussion_transfer
    end

    test "converts bare references in comment body to global reference" do
      referenced_discussion = create(:discussion, title: "I'm staying put", user: @member,
        repository: @old_repository)
      discussion_comment = create(:discussion_comment, discussion: @discussion,
        body: "Check out ##{referenced_discussion.number}")
      transferrer = DiscussionRepositoryTransferrer.for_new_transfer(@discussion,
        new_repository: @new_repository, actor: @owner)

      assert transferrer.start_transfer
      assert transferrer.complete_transfer
      expected = "Check out #{[@old_repository.nwo, "#", referenced_discussion.number].join}"
      assert_equal expected, discussion_comment.reload.body
    end

    test "enqueues job to update search index for new discussion" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      Timecop.freeze do
        assert transferrer.complete_transfer
        refute_nil transferrer.new_discussion
        guid = AddToSearchIndexJob.guid("discussion", transferrer.new_discussion.id)
        assert_enqueued_with job: AddToSearchIndexJob, args: ["discussion", transferrer.new_discussion.id, {
          "submitted_at" => Timestamp.from_time(Time.now), "guid" => guid
        }]
      end
    end

    test "repeated calls don't duplicate data" do
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @owner)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert_difference("DiscussionEvent.count") do
        assert transferrer.complete_transfer
      end
      assert_nil transferrer.error

      assert_no_difference("DiscussionEvent.count") do
        refute transferrer.complete_transfer
      end
      assert_equal "This discussion transfer has already finished.", transferrer.error
    end

    test "errors when actor no longer has sufficient access to the new repository" do
      @old_repository.add_member(@member, action: :write)
      @new_repository.add_member(@member, action: :write)
      transfer = create(:discussion_transfer, old_discussion: @discussion,
        new_repository: @new_repository, actor: @member)

      @new_repository.remove_member(@member)
      @new_repository.add_member(@member, action: :read)
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      refute transferrer.complete_transfer
      assert_equal "#{@member} does not have permission to finish transferring this " \
        "discussion.", transferrer.error
    end

    test "transfers labels and uses existing labels in the target repository" do
      label = create(:label, repository: @discussion.repository, name: "label")
      new_label = create(:label, repository: @new_repository, name: "label")
      @discussion.add_labels([label])

      transfer = create(:discussion_transfer,
        old_discussion: @discussion,
        new_repository: @new_repository,
        actor: @owner,
      )
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert_no_difference("@new_repository.labels.count") do
        transferrer.complete_transfer
      end
      assert_equal "label", transferrer.new_discussion.labels.reload.first.name
    end

    test "transfers labels and creates labels in the target repository" do
      label = create(:label, repository: @discussion.repository, name: "label")
      @discussion.add_labels([label])

      transfer = create(:discussion_transfer,
        old_discussion: @discussion,
        new_repository: @new_repository,
        actor: @owner,
      )
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)

      assert_difference("@new_repository.labels.count", 1) do
        transferrer.complete_transfer
      end
      assert_equal "label", transferrer.new_discussion.labels.reload.first.name
    end

    test "transfers closed discussion" do
      assert @discussion.close(actor: @owner)
      assert_predicate @discussion, :closed?

      transfer = create(:discussion_transfer,
        old_discussion: @discussion,
        new_repository: @new_repository,
        actor: @owner,
      )
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)
      assert transferrer.complete_transfer
      assert_predicate transferrer.new_discussion, :closed?
    end

    test "errors when the discussion is prematurely deleted" do
      transfer = create(:discussion_transfer,
        old_discussion: @discussion,
        new_repository: @new_repository,
        actor: @owner,
      )
      transferrer = DiscussionRepositoryTransferrer.for_continuing_transfer(transfer)
      DiscussionRepositoryTransferrer.any_instance.stubs(:old_discussion).returns(nil)

      refute transferrer.complete_transfer
      assert_equal "Original discussion has since been deleted.", transferrer.error
    end
  end
end
