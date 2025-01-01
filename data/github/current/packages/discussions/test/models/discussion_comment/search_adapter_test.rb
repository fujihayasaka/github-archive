# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentSearchAdapterTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
    @comment = create(:discussion_comment, discussion: @discussion)
  end

  context "#synchronize_search_index" do
    test "reindexes discussion when a comment body is updated" do
      @comment.body = "A new take on things!"
      guid = AddToSearchIndexJob.guid("discussion", @discussion.id)

      Timecop.freeze do
        assert_enqueued_with(job: AddToSearchIndexJob, args: ["discussion", @discussion.id, {
          "submitted_at" => Timestamp.from_time(Time.now), "guid" => guid
        }]) do
          assert @comment.save
        end
      end
    end
  end
end
