# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamPostToDiscussionConversionVerifierTest < GitHub::TestCase
  fixtures do
    @team_post = create(:discussion_post)
    @team_post_comment = create(:discussion_post_reply, discussion_post: @team_post)
    create(:reaction, subject: @team_post)
    create(:reaction, subject: @team_post_comment)
    create(:user_content_edit, user_content: @team_post)
    create(:user_content_edit, user_content: @team_post_comment)

    @discussion = create(:discussion)
    @discussion_comment = create(:discussion_comment, discussion: @discussion)
    create(:discussion_reaction, discussion: @discussion)
    create(:discussion_comment_reaction, discussion_comment: @discussion_comment)
    create(:discussion_edit, discussion: @discussion)
    create(:discussion_comment_edit, discussion_comment: @discussion_comment)
  end

  context ".call" do
    test "does not raise exception when relation counts match" do
      assert_nothing_raised do
        TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
      end
    end

    test "raises when discussion has an extra comment" do
      create(:discussion_comment, discussion: @discussion)
      assert_raises(TeamPostToDiscussionConversionVerifier::MissingCommentsError) do
        TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
      end
    end

    test "raises when discussion is missing a comment" do
      create(:discussion_post_reply, discussion_post: @team_post)
      assert_raises(TeamPostToDiscussionConversionVerifier::MissingCommentsError) do
        TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
      end
    end

    test "reports error when discussion has an extra edit" do
      Failbot.expects(:report).with("Team post has 1 edit while discussion has 2 edits")
      create(:discussion_edit, discussion: @discussion)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "reports error when discussion is missing an edit" do
      Failbot.expects(:report).with("Team post has 2 edits while discussion has 1 edit")
      create(:user_content_edit, user_content: @team_post)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "reports error when discussion has an extra reaction" do
      Failbot.expects(:report).with("Team post has 1 reaction while discussion has 2 reactions")
      create(:discussion_reaction, discussion: @discussion)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "raises when discussion is missing a reaction" do
      Failbot.expects(:report).with("Team post has 2 reactions while discussion has 1 reaction")
      create(:reaction, subject: @team_post)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "raises when discussion comment has an extra reaction" do
      Failbot.expects(:report).with("Team post has 1 reaction while discussion has 2 reactions")
      create(:discussion_comment_reaction, discussion_comment: @discussion_comment)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "raises when discussion comment is missing a reaction" do
      Failbot.expects(:report).with("Team post has 2 reactions while discussion has 1 reaction")
      create(:reaction, subject: @team_post_comment)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "raises when discussion comment has an extra edit" do
      Failbot.expects(:report).with("Team post has 1 comment edit while discussion has 2 comment edits")
      create(:discussion_comment_edit, discussion_comment: @discussion_comment)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end

    test "raises when discussion comment is missing an edit" do
      Failbot.expects(:report).with("Team post has 2 comment edits while discussion has 1 comment edit")
      create(:user_content_edit, user_content: @team_post_comment)
      TeamPostToDiscussionConversionVerifier.call(team_post: @team_post, discussion: @discussion)
    end
  end
end
