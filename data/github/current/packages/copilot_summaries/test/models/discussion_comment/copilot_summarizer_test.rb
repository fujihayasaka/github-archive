# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionComment::CopilotSummarizerTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
  end

  context "#copilot_api_reference_data" do
    test "returns a hash representing the comment for use as a CAPI reference" do
      creation_time = 1.week.ago
      author = create(:verified_user)
      comment = travel_to(creation_time) do
        create(:discussion_comment, discussion: @discussion, repository: @repo, user: author, body: "Great idea")
      end
      assert_equal 1, comment.reload.total_upvotes
      create_pair(:discussion_comment_reaction, content: "smile", discussion_comment: comment)
      summarizer = DiscussionComment::CopilotSummarizer.new(comment: comment)

      expected = {
        author: author.display_login,
        body: comment.body,
        createdAt: creation_time.iso8601,
        totalUpvotes: 1,
        reactionCounts: [{ reaction: "smile", count: 2 }],
      }
      assert_equal expected, summarizer.copilot_api_reference_data
    end

    test "strips images and links from comment body" do
      comment = create(:discussion_comment, discussion: @discussion, repository: @repo,
        body: "This is a [great](https://zombo.com) website! Please look:\n" \
          "<img src='some_file.png' alt='Magical views'>\n" \
          "![a user avatar](https://github.com/username.png) ![](/some-image-without-alt-text.jpeg)")
      summarizer = DiscussionComment::CopilotSummarizer.new(comment: comment)

      actual = summarizer.copilot_api_reference_data

      assert_equal "This is a great website! Please look:\nMagical views\na user avatar", actual[:body]
    end
  end
end
