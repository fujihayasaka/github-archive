# typed: true
# frozen_string_literal: true

# Public: Represents an interaction a user had with some other record, e.g.,
# opened an issue, subscribed to a pull request. Used to construct a 'Recently
# viewed' box on the user dashboard. This differs from an issue event in that
# it's not persisted and this could be used with records other than issues and
# PRs. This acts as a wrapper around other database records when we want to
# surface them on the dashboard.
class RecentInteraction
  attr_reader :interactable, :interaction, :occurred_at, :commenter, :comment_id

  delegate :repository, :repository_id, to: :interactable

  def initialize(interactable, interaction:, occurred_at:, commenter: nil, comment_id: nil)
    @interactable = interactable
    @interaction = interaction
    @occurred_at = occurred_at
    @commenter = commenter
    @comment_id = comment_id
  end

  # Public: Is the record a pull request?
  def pull_request?
    interactable.is_a?(PullRequest)
  end
end
