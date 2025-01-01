# typed: true
# frozen_string_literal: true

# Public: Used to check that a team post-to-discussion conversion did not fail.
class TeamPostToDiscussionConversionVerifier
  include GitHub::Memoizer

  class MissingCommentsError < StandardError; end

  # args - a Hash of arguments for verifying the conversion; supports keys:
  #   :team_post - a DiscussionPost
  #   :discussion - a Discussion
  sig { params(args: T.untyped).returns(T.untyped) }
  def self.call(args)
    new(**args).call
  end

  attr_reader :team_post, :discussion

  sig { params(team_post: T.untyped, discussion: T.untyped).void }
  def initialize(team_post:, discussion:)
    @team_post = team_post
    @discussion = discussion
  end

  sig { void }
  def call
    verify_comment_counts
    verify_reaction_counts
    verify_edit_counts
    verify_comment_edit_counts
    verify_comment_reaction_counts
  end

  private

  def verify_comment_counts
    unless team_post_comment_count == discussion_comment_count
      raise MissingCommentsError, error_message(team_post_comment_count, discussion_comment_count, "comment")
    end
  end

  def verify_reaction_counts
    unless team_post_reaction_count == discussion_reaction_count
      Failbot.report(error_message(team_post_reaction_count, discussion_reaction_count, "reaction"))
    end
  end

  def verify_edit_counts
    unless team_post_edit_count == discussion_edit_count
      Failbot.report(error_message(team_post_edit_count, discussion_edit_count, "edit"))
    end
  end

  def verify_comment_edit_counts
    unless team_post_comment_edit_count == discussion_comment_edit_count
      Failbot.report(error_message(team_post_comment_edit_count, discussion_comment_edit_count, "comment edit"))
    end
  end

  def verify_comment_reaction_counts
    unless team_post_comment_reaction_count == discussion_comment_reaction_count
      Failbot.report(error_message(team_post_comment_reaction_count,
        discussion_comment_reaction_count, "reaction"))
    end
  end

  def error_message(team_post_relation_count, discussion_relation_count, relation_name)
    team_post_units = relation_name.pluralize(team_post_relation_count)
    discussion_units = relation_name.pluralize(discussion_relation_count)
    "Team post has #{team_post_relation_count} #{team_post_units} while discussion has " \
      "#{discussion_relation_count} #{discussion_units}"
  end

  memoize def discussion_comment_count
    discussion.comments.count
  end

  memoize def discussion_reaction_count
    discussion.reactions.count
  end

  memoize def discussion_edit_count
    discussion.user_content_edits.count
  end

  memoize def discussion_comment_edit_count
    DiscussionCommentEdit.for_discussion(discussion.id).count
  end

  memoize def discussion_comment_reaction_count
    DiscussionCommentReaction.for_discussion(discussion.id).count
  end

  memoize def team_post_comment_count
    team_post_comments.size
  end

  memoize def team_post_reaction_count
    team_post.reactions.count
  end

  memoize def team_post_edit_count
    team_post.user_content_edits.count
  end

  memoize def team_post_comments
    team_post.replies.select(:id).includes(:reactions, :user_content_edits).to_a
  end

  memoize def team_post_comment_edit_count
    team_post_comments.sum { |reply| reply.user_content_edits.size }
  end

  memoize def team_post_comment_reaction_count
    team_post_comments.sum { |reply| reply.reactions.size }
  end
end
