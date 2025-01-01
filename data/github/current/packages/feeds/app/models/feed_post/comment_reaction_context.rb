# typed: true
# frozen_string_literal: true

class FeedPost::CommentReactionContext
  include GitHub::Memoizer

  def initialize(comment_ids:, viewer:)
    @comment_ids = comment_ids
    @viewer = viewer
  end

  memoize def viewer_reaction_contents_by_feed_post_comment_id
    return [] if GitHub.flipper[:disable_feed_post_reactions_on_dashboard_feed].enabled?(viewer)

    time_key = "for_you_feed.viewer_reaction_contents_by_feed_post_comment_id.time"
    GitHub.dogstats.time(time_key) do
      Reaction.
        where(subject_type: "FeedPostComment", subject_id: comment_ids, user: viewer).
        pluck(:subject_id, :content).
        each_with_object({}) do |(comment_id, content), result|
          result[comment_id] ||= []
          result[comment_id].push(content)
        end
    end
  end

  private

  attr_reader :comment_ids, :viewer
end
