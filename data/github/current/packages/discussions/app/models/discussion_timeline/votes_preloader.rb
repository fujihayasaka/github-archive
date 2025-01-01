# typed: true
# frozen_string_literal: true

class DiscussionTimeline::VotesPreloader
  include GitHub::Memoizer

  delegate :repository, to: :discussion

  sig { params(timeline: T.untyped).returns(T.untyped) }
  def self.load_for(timeline)
    timeline.record_show_stats_distribution(:preload_votes) do
      new(
        viewer: timeline.viewer,
        discussion: timeline.discussion,
        comments: timeline.top_level_comments
      ).tap do |preloader|
        preloader.preload
        timeline.votes_preloader = preloader
      end
    end
  end

  sig { params(viewer: T.untyped, discussion: T.untyped, comments: T.untyped).void }
  def initialize(viewer:, discussion:, comments:)
    @viewer = viewer
    @discussion = discussion
    @comments = comments
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def vote_for(discussion_or_comment)
    if discussion_or_comment.is_a?(Discussion)
      discussion_vote
    else
      comment_votes_by_comment_id[discussion_or_comment.id]&.first
    end
  end

  sig { returns(T.untyped) }
  def preload
    discussion_vote
    comment_votes_by_comment_id
  end

  private

  attr_reader :viewer, :discussion, :comments

  memoize def comment_votes_by_comment_id
    DiscussionCommentVote
      .for_comment(comments.map(&:id))
      .for_discussion(discussion)
      .for_user(viewer)
      .group_by(&:comment_id)
  end

  memoize def discussion_vote
    DiscussionVote.for_discussion(discussion).for_user(viewer).first
  end
end
