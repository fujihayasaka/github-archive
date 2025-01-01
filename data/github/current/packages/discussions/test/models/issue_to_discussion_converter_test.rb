# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueToDiscussionConverterTest < GitHub::TestCase
  include NewsiesHelper
  include UploadableTestHelpers
  include HydroTestHelpers

  fixtures do
    @owner, @author, @commenter = create_list(:verified_user, 3).each do |user|
      enable_notifications_for_user(user, enabled_handlers: %w[web])
    end

    @repo = create(:repository, owner: @owner, has_discussions: true)
    @issue = create(:issue, repository: @repo, user: @author)
    @label = create(:label, repository: @repo, name: "Test")
    @issue.replace_labels([@label])
    @issue_without_comments = create(:issue, repository: @repo)
    @issue_comment = create(:issue_comment, issue: @issue, repository: @repo, user: @commenter, created_at: 3.seconds.ago)
    @category = create(:discussion_category, repository: @repo)

    @min_comment = create(:issue_comment, issue: @issue, repository: @repo, created_at: 2.seconds.ago)
    @min_comment.set_minimized(@owner, "irrelevant", "OFF_TOPIC", @min_comment.user)

    @email_comment = create(:issue_comment, issue: @issue, repository: @repo, formatter: "email", created_at: 1.second.ago)

    user_to_delete = create(:user)
    @ghost_comment = create(:issue_comment, issue: @issue, repository: @repo, user: user_to_delete)
    user_to_delete.delete
    @ghost_comment.reload
  end

  context "#prepare_for_conversion" do
    test "creates a new discussion with the same information except for number" do
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.prepare_for_conversion

      refute_nil converter.discussion
      assert_predicate converter.discussion, :persisted?
      assert_predicate converter.discussion, :converting?
      assert_equal @issue.title, converter.discussion.title
      assert_equal @issue.body, converter.discussion.body
      assert_equal @issue.repository, converter.discussion.repository
      assert_equal @issue.user, converter.discussion.user
      refute_equal @issue.number, converter.discussion.number
      assert_equal @issue, converter.discussion.issue

      general_category = @repo.discussion_categories.find_by!(name: DiscussionCategory::GENERAL_NAME)
      assert_equal general_category, converter.discussion.category
    end

    test "places the new discussion in a specified category" do
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner, category: @category)

      assert converter.prepare_for_conversion
      assert_equal @category, converter.discussion.category
    end

    test "sets bumped_at to latest issue comment created_at" do
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner, category: @category)

      assert converter.prepare_for_conversion
      assert_equal @ghost_comment.created_at, converter.discussion.reload.bumped_at
    end

    test "sets bumped_at to issue created_at if no comments are present" do
      issue = create(:issue, repository: @repo, user: @author)
      converter = IssueToDiscussionConverter.new(issue, actor: @owner, category: @category)

      assert converter.prepare_for_conversion
      assert_equal issue.created_at, converter.discussion.reload.bumped_at
    end

    test "can convert an issue whose author has been deleted" do
      ghost_issue = create(:issue, repository: @repo)
      ghost_issue.user.delete
      assert_nil ghost_issue.reload.user
      converter = IssueToDiscussionConverter.new(ghost_issue, actor: @owner)

      assert converter.prepare_for_conversion

      refute_nil converter.discussion
      assert_predicate converter.discussion, :persisted?
      assert_predicate converter.discussion, :converting?
      assert_equal ghost_issue.title, converter.discussion.title
      assert_equal ghost_issue.body, converter.discussion.body
      assert_equal ghost_issue.repository, converter.discussion.repository
      assert_predicate converter.discussion.user, :ghost?
      refute_equal ghost_issue.number, converter.discussion.number
      assert_equal ghost_issue, converter.discussion.issue
    end

    test "returns false if invalid for some reason" do
      assert @issue.close
      @issue.update_attribute(:title, "")
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      refute converter.prepare_for_conversion

      refute converter.discussion.persisted?
      assert_equal "Title can't be blank", converter.discussion.errors.full_messages.join(",")
    end

    test "returns true if already converted" do
      converter1 = IssueToDiscussionConverter.new(@issue, actor: @owner)
      assert converter1.prepare_for_conversion

      converter2 = IssueToDiscussionConverter.new(@issue, actor: @owner)
      assert converter2.prepare_for_conversion

      assert_equal converter1.discussion, converter2.discussion
    end

    test "returns false when the user lacks permission to convert the issue" do
      rando = create(:user)
      converter = IssueToDiscussionConverter.new(@issue, actor: rando)

      refute converter.prepare_for_conversion
      assert_nil converter.discussion
    end

    test "allows converting to discussion in announcements category if author cannot create announcements" do
      announcements = create(:discussion_category,
        repository: @repo,
        supports_announcements: true,
      )
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner, category: announcements)
      assert converter.prepare_for_conversion
      assert converter.discussion.persisted?
      assert_empty converter.discussion.errors
    end
  end

  context "#finish_conversion" do
    test "does not delete the issue" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      converter.finish_conversion

      assert Issue.exists?(@issue.id)
    end

    test "locks the issue" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      refute_predicate @issue, :locked?
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      converter.finish_conversion

      assert_predicate @issue.reload, :locked?
    end

    test "sets converted_at to the current time" do
      now = Time.now.beginning_of_minute

      Timecop.freeze(now) do
        discussion = Discussion.from_issue(@issue, category: @category)
        discussion.save!
        converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

        assert converter.finish_conversion, "should return true on success"

        assert discussion.reload.converted_at, now
      end
    end

    test "copies over the comments and reactions, plus updates the state" do
      issue_reaction = @issue.react(actor: @owner, content: "+1")
      issue_comment_reaction = @issue_comment.react(actor: @owner, content: "heart")
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"

      discussion.reload

      assert_equal 4, discussion.comments.count
      assert_equal 1, discussion.reactions.count

      # Ensure that counter caches are updated
      assert_equal 4, discussion.comment_count
      assert_equal 4, discussion.direct_comment_count

      assert_predicate discussion, :open?
      assert_predicate discussion, :no_error?

      reaction = discussion.reactions.first
      assert_equal issue_reaction.content, reaction.content
      assert_equal issue_reaction.user, reaction.user

      comment = discussion.comments.first
      assert_equal 1, comment.reactions.count
      assert_equal @issue_comment.body, comment.body
      assert_equal @issue_comment.user, comment.user
      assert_equal @issue_comment.created_at, comment.created_at
      assert_equal @issue_comment.updated_at, comment.updated_at
      assert_equal @issue_comment.formatter, comment.formatter

      comment_reaction = comment.reactions.first
      assert_equal issue_comment_reaction.content, comment_reaction.content
      assert_equal issue_comment_reaction.user, comment_reaction.user

      min_comment = discussion.comments.second
      assert_predicate min_comment, :minimized?
      assert_equal @min_comment.body, min_comment.body
      assert_equal @min_comment.user, min_comment.user
      assert_equal @min_comment.created_at, min_comment.created_at
      assert_equal @min_comment.updated_at, min_comment.updated_at
      assert_equal @min_comment.formatter, min_comment.formatter
      assert_equal @min_comment.minimized_reason, min_comment.minimized_reason
      assert_equal @min_comment.comment_hidden_reason, min_comment.comment_hidden_reason

      email_comment = discussion.comments.third
      assert_equal @email_comment.body, email_comment.body
      assert_equal @email_comment.user, email_comment.user
      assert_equal @email_comment.created_at, email_comment.created_at
      assert_equal @email_comment.updated_at, email_comment.updated_at
      assert_equal @email_comment.formatter, email_comment.formatter

      ghost_comment = discussion.comments.fourth
      assert_equal @ghost_comment.body, ghost_comment.body
      assert_predicate ghost_comment.user, :ghost?
      assert_equal @ghost_comment.created_at, ghost_comment.created_at
      assert_equal @ghost_comment.updated_at, ghost_comment.updated_at
      assert_equal @ghost_comment.formatter, ghost_comment.formatter
    end

    # https://sentry.io/organizations/github/issues/1927684701/events/f9bbb7e64d0c46798e7731084ca2d601/?project=1885898&statsPeriod=14d
    test "conversion succeeds if ghost comment includes an attachment" do
      uploader = create(:user)
      asset = save_file_for_uploadable(UserAsset.new(uploader: uploader))
      comment_body = "<p><img src=#{s3_asset_url(uploader.id, asset.id, asset.guid)}></p>"

      @ghost_comment.update!(body: comment_body)

      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"
    end

    test "copies over the labels" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!

      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"

      discussion.reload
      assert_equal @issue.labels, discussion.labels
    end


    test "copies over edit history for issue body" do
      old_body = @issue.body
      @issue.update_body("New body", @owner)

      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"

      discussion.reload

      assert_equal "New body", discussion.body
      assert_predicate discussion, :edited?, "discussion should be edited"
      assert_equal @owner, discussion.editor
      assert_equal 2, discussion.user_content_edits.size
      assert_includes discussion.user_content_edits.map(&:diff), old_body
    end

    test "copies over edit history for issue comments" do
      old_comment_body = @issue_comment.body
      @issue_comment.update_body("New body", @owner)

      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"

      discussion.reload
      discussion_comment = discussion.comments.first

      assert_equal "New body", discussion_comment.body
      assert_predicate discussion_comment, :edited?, "discussion comment should be edited"
      assert_equal @owner, discussion_comment.editor
      assert_equal 2, discussion_comment.user_content_edits.size
    end

    test "copies over subscriptions respecting ignore status", skip_if_feature_enabled: :notifyd_issue_watch_activity_notify do
      subscriber = create(:user)
      @issue.subscribe(subscriber, "manual")

      ignoring_subscriber = create(:user)
      @issue.subscribe(ignoring_subscriber, "manual")
      @issue.unsubscribe(ignoring_subscriber)

      assert @issue.subscribed?(subscriber), "expected subscriber to be subscribed to issue"
      refute @issue.subscribed?(ignoring_subscriber), "expected subscriber to not be subscribed to issue"

      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      perform_enqueued_jobs(only: [Newsies::CopyThreadSubscribersJob]) do
        assert converter.finish_conversion, "should return true on success"
      end

      assert discussion.subscribed?(subscriber), "expected subscriber to be subscribed to discussion"
      assert discussion.subscribed?(@issue.user), "expected @issue.user to be subscribed to discussion"
      refute discussion.subscribed?(ignoring_subscriber), "expected @ignoring_subscriber to not be subscribed to discussion"
      refute discussion.subscription_status(ignoring_subscriber).is_valid, "expected @ignoring_subscriber to not have a valid subscription"
    end

    test "deletes discussion and reopens issue on conversion failure" do
      discussion = Discussion.from_issue(@issue, category: @category)
      @issue.update!(state: :closed)
      discussion.category = @issue.repository.discussion_categories.last
      discussion.save!
      @issue_comment.update_attribute(:body, "")
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner,
        issue_originally_open: true)

      assert_no_difference("DiscussionComment.count") do
        assert_difference("Discussion.count", -1) do
          assert_difference("@issue.events.reopens.count") do
            refute converter.finish_conversion, "should return false on error"
          end
        end
      end

      refute Discussion.exists?(discussion.id)
      assert_predicate @issue.reload, :open?
      event = @issue.events.reopens.where(actor_id: @owner).last
      refute_nil event, "should have created an IssueEvent by the given actor"
    end

    test "unlocks issue on conversion failure" do
      discussion = Discussion.from_issue(@issue, category: @category)
      @issue.update!(state: :closed)
      refute_predicate @issue, :locked?
      discussion.category = @issue.repository.discussion_categories.last
      discussion.save!
      @issue_comment.update_attribute(:body, "")
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner,
        issue_originally_open: true)

      assert_no_difference("DiscussionComment.count") do
        assert_difference("Discussion.count", -1) do
          assert_difference("@issue.events.reopens.count") do
            refute converter.finish_conversion, "should return false on error"
          end
        end
      end

      refute_predicate @issue.reload, :locked?
    end

    test "does not reopen issue that started as closed when conversion fails" do
      discussion = Discussion.from_issue(@issue, category: @category)
      @issue.update!(state: :closed)
      discussion.save!
      @issue_comment.update_attribute(:body, "")
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner,
        issue_originally_open: false)

      assert_no_difference(["DiscussionComment.count", "@issue.events.reopens.count"]) do
        assert_difference("Discussion.count", -1) do
          refute converter.finish_conversion, "should return false on error"
        end
      end

      refute Discussion.exists?(discussion.id)
      refute_predicate @issue.reload, :open?
    end

    test "updates discussion if conversion fails and discussion can't be deleted" do
      discussion = Discussion.from_issue(@issue, category: @category)
      @issue.update!(state: :closed)
      discussion.save!
      @issue_comment.update_attribute(:body, "")
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)
      Discussion.any_instance.stubs(:destroy).returns(false)

      assert_no_difference(["DiscussionComment.count", "IssueEvent.count"]) do
        refute converter.finish_conversion, "should return false on error"
      end

      assert_predicate @issue.reload, :closed?
      assert Discussion.exists?(discussion.id)
      assert_predicate discussion.reload, :error?
      assert_predicate discussion, :reset_conversion_failure?
    end

    # We think this is what happened to vercel/next.js#861 as mentioned in https://github.com/github/discussions/issues/1280
    # Some code within the transaction raised an `ActiveRecord::Rollback`, which was rescued by the transaction block.
    # Since `success` defaulted to true, the conversion went ahead and deleted the original issue,
    # even though the comments/reactions/etc were not transferred over (because the transaction was rolled back).
    test "doesn't delete the issue if the transaction rolled back without a validation error" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!

      # This might be contrived, but _something_ seems to have raised ActiveRecord::Rollback
      # within the transaction on production.
      discussion.stubs(:save!).raises(ActiveRecord::Rollback)
      @issue.stubs(discussion: discussion)

      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert_no_difference("DiscussionComment.count") do
        assert_difference("Discussion.count", -1) do
          refute converter.finish_conversion, "should return false on error"
        end
      end

      refute Discussion.exists?(discussion.id)
      assert_predicate @issue.reload, :open?
    end

    test "cleans up a failed conversion if some other exception is raised within the transaction" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!

      error = RuntimeError.new("hi")
      discussion.stubs(:save!).raises(error)
      @issue.stubs(discussion: discussion)

      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert_no_difference("DiscussionComment.count") do
        assert_difference("Discussion.count", -1) do
          assert_raises(RuntimeError) do
            converter.finish_conversion
          end
        end
      end

      refute Discussion.exists?(discussion.id)
      assert_predicate @issue.reload, :open?
    end

    test "cleans up a failed conversion if closing issue fails" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!

      @issue.stubs(:close).returns(false)

      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert_no_difference("DiscussionComment.count") do
        assert_difference("Discussion.count", -1) do
          converter.finish_conversion
        end
      end

      refute Discussion.exists?(discussion.id)
      assert_predicate @issue.reload, :open?
    end

    test "doesn't fail due to RateLimitedCreation" do
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!

      GitHub::RateLimitedCreation.use_custom_limits(user_minute: 0) do
        converter = IssueToDiscussionConverter.new(@issue, actor: @owner)
        assert converter.finish_conversion, "should return true on success"
        refute_nil discussion.reload.converted_at
      end
    end

    test "sets discussion to lock state if the issue is locked" do
      @issue.lock(@owner)
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert_difference("DiscussionEvent.locked.count") do
        assert converter.finish_conversion, "should return true on success"
      end
      assert_predicate discussion.reload, :locked?
      event = discussion.events.locked.last
      assert_equal @owner, event.actor
    end

    test "succeeds even if author is blocked" do
      @owner.block(@author)
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"
    end

    test "succeeds even if commenter is blocked" do
      @owner.block(@commenter)
      discussion = Discussion.from_issue(@issue, category: @category)
      discussion.save!
      converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

      assert converter.finish_conversion, "should return true on success"
      assert_equal 4, discussion.comments.count
    end

    context "conversion verification" do
      test "calls verifiy to check that conversion was actually successful" do
        discussion = Discussion.from_issue(@issue, category: @category)
        discussion.save!
        converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

        IssueToDiscussionConversionVerifier.expects(:verify!).with(@issue, discussion)

        converter.finish_conversion
      end

      test "cleans up and retries if call to verifier raises a verification error" do
        discussion = Discussion.from_issue(@issue, category: @category)
        discussion.save!
        converter = IssueToDiscussionConverter.new(@issue, actor: @owner)

        IssueToDiscussionConversionVerifier
          .expects(:verify!)
          .with(@issue, discussion)
          .raises(IssueToDiscussionConversionVerifier::MissingCommentsError)

        assert_raises IssueToDiscussionConversionVerifier::MissingCommentsError do
          converter.finish_conversion
        end

        assert_nil @issue.reload.discussion
        refute Discussion.exists?(discussion.id)
      end

      test "creates conversion event and closes issue" do
        discussion = Discussion.from_issue(@issue, category: @category)
        discussion.save!
        converter = IssueToDiscussionConverter.new(@issue, actor: @owner)
        refute_predicate @issue, :closed?
        assert_nil @issue.events.find_by(event: "closed")
        assert_nil @issue.events.find_by(event: "converted_to_discussion")

        assert converter.finish_conversion, "should return true on success"
        assert_predicate @issue.reload, :closed?
        assert_nil @issue.events.find_by(event: "closed")
        refute_nil @issue.events.find_by(event: "converted_to_discussion")
      end

      test "creates a new discussion and emits a hydro event" do
        travel_to Time.now do
          converter = IssueToDiscussionConverter.new(@issue, actor: @owner)
          assert converter.prepare_for_conversion

          reset_hydro

          converter.finish_conversion

          discussion = converter.discussion

          message_v2 = {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            repository_id: discussion.repository.id,
            repository: Hydro::EntitySerializer.repository(discussion.repository),
            repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
            actor_id: @owner.id,
            actor: Hydro::EntitySerializer.user(@owner),
            discussion_id: discussion.id,
            discussion: Hydro::EntitySerializer.discussion(discussion),
            lock_status: :LOCK_STATUS_UNLOCKED,
            pin_status: :PIN_STATUS_UNPINNED,
            announcement: false,
            org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
            action: :ACTION_DISCUSSION_UPDATED,
            action_timestamp: Time.now,
            discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
            category_id: discussion.category.id,
            # the discussion is in the process of being converted from an issue
            # so the issue_id is not yet set and the converted_from_issue flag is false
            converted_from_issue: true,
            converted_issue_id: discussion.issue_id,
            specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
            specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
            state: :STATE_OPEN,
            state_reason: :STATE_REASON_UNKNOWN,
          }

          assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
          assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        end
      end
    end
  end

  def s3_asset_url(user_id, asset_id, guid)
    url = "#{GitHub.s3_asset_host}assets/%d/%d/%s.gif" % [
      user_id, asset_id, guid]
  end
end
