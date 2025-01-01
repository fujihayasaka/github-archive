# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamPostToDiscussionConverterTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @admin = create(:verified_user)
    @user = create(:verified_user)
    @user_to_delete = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @repo = create(:repository, owner: @org, has_discussions: true)
    @category = create(:discussion_category, repository: @repo)
    @team = create(:team, organization: @org)
    @org.add_member(@user)
    @org.add_member(@user_to_delete)
    @team.add_member(@user)
    @team.add_member(@user_to_delete)
    @team_post1 = create(:discussion_post, team: @team, user: @user)
    @team_post2 = create(:discussion_post, team: @team, user: @user)

    @team_post_deleted_owner = create(:discussion_post, team: @team, user: @user_to_delete)

    @body = "Hello world"
    @title = "My favorite places to visit"
    @created_at = 1.month.ago.freeze
    @team_post = travel_to(@created_at) do
      create(:discussion_post, team: @team, user: @user, body: @body, title: @title)
    end
    @updated_at = 1.week.ago.freeze
    travel_to(@updated_at) { @team_post.touch }
  end

  setup do
    @converter = TeamPostToDiscussionConverter.new(@team_post, actor: @user, repository: @repo)
  end

  context "#prepare_for_conversion" do
    test "creates a discussion for team post" do
      assert_nil @team_post.discussion, "expected team post to not already have a discussion for it"

      assert_difference({ "Discussion.count" => 1, "DiscussionCategory.count" => 1 }) do
        assert_logged("event" => "prepare_team_post_to_discussion_conversion_finished") do
          assert_logged("event" => "preparing_for_converting_team_post_to_discussion") do
            refute_logged("event" => "team_post_already_converted_to_discussion") do
              refute_logged("event" => "prepare_team_post_to_discussion_conversion_failed") do
                assert @converter.prepare_for_conversion
              end
            end
          end
        end
      end

      discussion = @team_post.reload.discussion
      refute_nil discussion
      assert_equal @user, discussion.user
      assert_in_delta @created_at, discussion.created_at, 1.minute
      assert_in_delta @created_at, discussion.bumped_at, 1.minute
      assert_in_delta @updated_at, discussion.updated_at, 1.minute
      assert_equal @body, discussion.body
      assert_equal @title, discussion.title
      assert_equal 0, discussion.comment_count
      assert_equal @team_post.id, discussion.team_post_id
      assert_predicate discussion, :converting?
      assert_nil discussion.converted_at
      refute_predicate discussion, :user_hidden?
      assert_equal @repo, discussion.repository
      refute_nil discussion.category
      assert_equal DiscussionCategory::TEAM_POST_MIGRATION_CATEGORY[:name], discussion.category.name
      assert_equal @repo, discussion.repository
    end

    test "returns false if already at maximum number of categories" do
      DiscussionCategory.stub_const(:MAX_CATEGORIES_PER_REPO, 10) do
        create_list(:discussion_category, 3, repository: @repo)
        refute @converter.prepare_for_conversion
      end
    end
  end

  context "#finish_conversion" do
    test "returns false if the discussion doesn't exist on the team post" do
      refute @converter.finish_conversion
    end

    test "rolls back when conversion fails" do
      team_post_comment = create(:discussion_post_reply, discussion_post: @team_post)
      create(:user_content_edit, user_content: team_post_comment)
      DiscussionCommentEdit.stubs(:create!).raises(ActiveRecord::RecordInvalid)

      assert @converter.prepare_for_conversion
      discussion = @team_post.reload.discussion
      refute_nil discussion, "discussion should now exist since #prepare_for_conversion creates it"

      assert_difference(-> { Discussion.count }, -1) do
        assert_no_difference("DiscussionCommentEdit.count") do
          assert_no_difference("DiscussionCommentReaction.count") do
            refute @converter.finish_conversion, "should return false on failure"
          end
        end
      end

      refute Discussion.exists?(discussion.id)
      assert_nil @team_post.reload.discussion
    end

    test "finishes converting the discussion" do
      team_post_reaction = create(:reaction, subject: @team_post)
      team_post_edit = create(:user_content_edit, user_content: @team_post, diff: "foo")
      team_post_comment = create(:discussion_post_reply, discussion_post: @team_post)
      team_post_comment_reaction = create(:reaction, content: "+1", subject: team_post_comment)
      team_post_comment_edit = create(:user_content_edit, user_content: team_post_comment, diff: "bar")
      assert @converter.prepare_for_conversion, "need a team post that has been prepared for conversion"
      discussion = @team_post.reload.discussion
      assert_nil discussion.converted_at
      conversion_finish_time = 1.day.from_now

      travel_to(conversion_finish_time) do
        assert_difference({
          "DiscussionComment.count" => 1,
          "DiscussionCommentReaction.count" => 1,
          "DiscussionReaction.count" => 1,
        }) do
          assert_logged("event" => "result_of_team_post_to_discussion_conversion") do
            assert_logged("event" => "successfully_finished_converting_team_post_to_discussion") do
              assert_logged("event" => "supposedly_finished_team_post_to_discussion_conversion") do
                assert_logged("event" => "discussion_saved") do
                  assert_logged("event" => "preparing_to_save_discussion") do
                    assert_logged("event" => "attempting_finish_team_post_to_discussion_conversion") do
                      refute_logged("event" => "clean_up_after_failed_team_post_to_discussion_conversion_started") do
                        refute_logged("event" => "failed_to_finish_converting_team_post_to_discussion") do
                          assert @converter.finish_conversion
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        refute_nil discussion.reload.converted_at, "should have set conversion time"
        assert_in_delta conversion_finish_time, discussion.converted_at, 1.minute
        refute_predicate discussion, :converting?
        assert_predicate discussion, :open?
      end
    end

    test "can convert a discussion with a deleted owner" do
      @user_to_delete.destroy

      converter = TeamPostToDiscussionConverter.new(@team_post_deleted_owner, actor: @user, repository: @repo)
      converter.prepare_for_conversion
      discussion = @team_post_deleted_owner.reload.discussion
      assert_nil discussion.converted_at
      conversion_finish_time = 1.day.from_now

      travel_to(conversion_finish_time) do
        assert converter.finish_conversion

        refute_nil discussion.reload.converted_at, "should have set conversion time"
        assert_in_delta conversion_finish_time, discussion.converted_at, 1.minute
        refute_predicate discussion, :converting?
        assert_predicate discussion, :open?
      end
    end

    test "copies the reactions to the discussion" do
      content = "+1"
      reactor = create(:user)
      created_at = 1.hour.ago
      team_post_reaction = travel_to(created_at) do
        create(:reaction, content: content, user: reactor, subject: @team_post)
      end
      updated_at = 15.minutes.ago
      travel_to(updated_at) { team_post_reaction.touch }

      @converter.prepare_for_conversion

      assert_difference(-> { DiscussionReaction.count }) do
        assert @converter.finish_conversion, "should return true on success"
      end

      discussion = @team_post.reload.discussion
      refute_nil discussion
      assert_equal 1, discussion.reactions.count
      reaction = discussion.reactions.last
      assert_equal reactor.id, reaction.user_id
      assert_equal content, reaction.content
      assert_in_delta created_at, reaction.created_at, 1.minute
      assert_in_delta updated_at, reaction.updated_at, 1.minute
      refute_predicate reaction, :user_hidden?
    end

    test "copies the subscriptions to the discussion" do
      subscriber = create(:verified_user)
      @org.add_member(subscriber)
      @team.add_member(subscriber)
      @team_post.subscribe(subscriber, "manual")

      assert @team_post.subscribed?(subscriber), "expected subscriber to be subscribed to discussion"

      assert @converter.prepare_for_conversion

      perform_enqueued_jobs(only: [Newsies::CopyThreadSubscribersJob]) do
        assert @converter.finish_conversion, "should return true on success"
      end

      discussion = @team_post.reload.discussion

      assert discussion.subscribed?(subscriber), "should be subscribed to discussion"
    end

    test "copies the comments to the discussion" do
      body = "Hello world"
      formatter = "email"
      created_at = 1.day.ago
      reply = travel_to(created_at) do
        create(:discussion_post_reply, body: body, user: @user, discussion_post: @team_post, formatter: formatter)
      end
      updated_at = 1.hour.ago
      travel_to(updated_at) { reply.touch }

      assert @converter.prepare_for_conversion

      assert_difference(-> { DiscussionComment.count }) do
        assert @converter.finish_conversion, "should return true on success"
      end

      discussion = @team_post.reload.discussion
      refute_nil discussion
      comment = discussion.comments.last
      refute_nil comment
      assert_equal body, comment.body
      assert_in_delta created_at, comment.created_at, 1.minute
      assert_in_delta updated_at, comment.updated_at, 1.minute
      assert_equal @user.id, comment.user_id
      assert_equal formatter.to_sym, comment.formatter
      assert_equal 1, discussion.comment_count, "should have updated comment count on discussion"
    end


    test "copies the reactions to comments to the discussion" do
      reply = create(:discussion_post_reply, discussion_post: @team_post)
      content = "heart"
      reactor = create(:user)
      created_at = 1.week.ago
      reaction = travel_to(created_at) { create(:reaction, subject: reply, content: content, user: reactor) }
      updated_at = 1.day.ago
      travel_to(updated_at) { reaction.touch }

      assert @converter.prepare_for_conversion

      assert_difference(-> { DiscussionCommentReaction.count }) do
        assert @converter.finish_conversion, "should return true on success"
      end

      discussion = @team_post.reload.discussion
      refute_nil discussion
      comment = discussion.comments.last
      refute_nil comment
      reaction = comment.reactions.last
      refute_nil reaction
      assert_equal content, reaction.content
      assert_equal reactor.id, reaction.user_id
      assert_in_delta created_at, reaction.created_at, 1.minute
      assert_in_delta updated_at, reaction.updated_at, 1.minute
      refute_predicate reaction, :user_hidden?
    end

    test "copies the edits to the discussion" do
      old_body = @team_post.body
      editor = create(:user)
      @team_post.update_body("New body", editor)
      assert_equal 2, @team_post.user_content_edits.count, "should have an edit for the original and the update"
      team_post_edit1, team_post_edit2 = @team_post.user_content_edits

      assert @converter.prepare_for_conversion

      assert_difference(-> { DiscussionEdit.count }, 2) do
        assert @converter.finish_conversion, "should return true on success"
      end

      discussion = @team_post.reload.discussion
      refute_nil discussion
      assert_predicate discussion, :edited?, "should be edited"
      assert_equal "New body", discussion.body
      assert_equal editor, discussion.editor, "should be edited by user"

      assert_equal 2, discussion.user_content_edits.size
      discussion_edit1, discussion_edit2 = discussion.user_content_edits

      assert_equal old_body, discussion_edit1.diff
      assert_equal team_post_edit1.editor_id, discussion_edit1.editor_id
      assert_in_delta team_post_edit1.created_at, discussion_edit1.created_at, 1.minute
      assert_in_delta team_post_edit1.updated_at, discussion_edit1.updated_at, 1.minute
      assert_in_delta team_post_edit1.edited_at, discussion_edit1.edited_at, 1.minute

      assert_equal "New body", discussion_edit2.diff
      assert_equal team_post_edit2.editor_id, discussion_edit2.editor_id
      assert_in_delta team_post_edit2.created_at, discussion_edit2.created_at, 1.minute
      assert_in_delta team_post_edit2.updated_at, discussion_edit2.updated_at, 1.minute
      assert_in_delta team_post_edit2.edited_at, discussion_edit2.edited_at, 1.minute
    end

    test "copies the edits to comments to the discussion" do
      reply = create(:discussion_post_reply, discussion_post: @team_post)
      old_body = reply.body
      editor = create(:user)
      edited_at = 1.day.ago
      travel_to(edited_at) do
        assert reply.update_body("New body", editor), "need body update of reply to success"
      end
      assert_equal 2, reply.user_content_edits.size, "should have two edits on the team post comment"
      reply_edit1, reply_edit2 = reply.user_content_edits

      assert @converter.prepare_for_conversion

      assert_difference(-> { DiscussionCommentEdit.count }, 2) do
        assert @converter.finish_conversion, "should return true on success"
      end

      discussion = @team_post.reload.discussion
      refute_nil discussion
      comment = discussion.comments.to_a.detect { |c| c.body == "New body" }
      refute_nil comment
      assert_predicate comment, :edited?, "should be edited"
      assert_equal editor.id, comment.editor.id, "should be edited by user"

      assert_equal 2, comment.user_content_edits.size, "should have the original comment and its update"
      discussion_edits = comment.user_content_edits.order(:id).to_a

      discussion_edit1 = discussion_edits.detect { |edit| edit.diff == old_body }
      refute_nil discussion_edit1
      assert_equal reply_edit1.editor_id, discussion_edit1.editor_id
      assert_in_delta edited_at, discussion_edit1.created_at, 1.minute
      assert_in_delta reply_edit1.created_at, discussion_edit1.created_at, 1.minute
      assert_in_delta reply_edit1.updated_at, discussion_edit1.updated_at, 1.minute

      discussion_edit2 = discussion_edits.detect { |edit| edit.diff == "New body" }
      refute_nil discussion_edit2
      assert_equal editor.id, discussion_edit2.editor.id
      assert_in_delta edited_at, discussion_edit2.edited_at, 1.minute
      assert_in_delta reply_edit2.created_at, discussion_edit2.created_at, 1.minute
      assert_in_delta reply_edit2.updated_at, discussion_edit2.updated_at, 1.minute

      assert_equal discussion_edit2, comment.async_latest_user_content_edit.sync
    end
  end

  test "cleans up a failed conversion if some other exception is raised within the transaction" do
    discussion = Discussion.from_team_discussion(@team_post, repository: @repo, category: @category)
    discussion.save!

    error = RuntimeError.new("hi")
    discussion.stubs(:save!).raises(error)
    @team_post.stubs(discussion: discussion)

    assert_no_difference("DiscussionComment.count") do
      assert_difference("Discussion.count", -1) do
        assert_raises(RuntimeError) do
          @converter.finish_conversion
        end
      end
    end
    refute Discussion.exists?(discussion.id)
    assert @team_post.reload
  end
end
