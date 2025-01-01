# typed: true
# frozen_string_literal: true

module DiscussionPost::DiscussionsDependency
  extend T::Helpers
  extend T::Sig

  requires_ancestor { DiscussionPost }

  # Public: Determine whether this Team Discussion is eligible to be converted to a Discussion.
  sig { returns T::Boolean }
  def can_be_converted_to_discussion?
    # Already has a discussion created from team discussion
    return false if discussion

    true
  end

  sig { params(actor: T.nilable(User), repository: T.nilable(Repository)).returns(T::Boolean) }
  def can_be_transferred_to_discussion?(actor, repository)
    return false if actor.nil? || repository.nil?

    ::Permissions::Enforcer.authorize(
      action: :transfer_team_discussion_to_discussions,
      actor: actor,
      subject: repository,
      context: {
        current_team_id: T.must(self.team).id,
        current_team_organization_id: T.must(T.must(self.team).organization).id
      }
    ).allow?
  end

  sig { returns T::Boolean }
  def mark_as_converted_to_discussion
    success = false
    converted_discussion = Discussion.converted_from_team_discussion(self).first
    if converted_discussion
      success = self.update(transferred_discussion_id: converted_discussion.id)
    end
    success
  end
end
