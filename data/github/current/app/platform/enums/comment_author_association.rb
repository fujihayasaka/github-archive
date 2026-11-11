# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CommentAuthorAssociation < Platform::Enums::Base
      description "A comment author association with repository."

      value "MEMBER", "Author is a member of the organization that owns the repository.", value: :member
      value "OWNER", "Author is the owner of the repository.", value: :owner
      value "MANNEQUIN", "Author is a placeholder for an unclaimed user.", value: :mannequin
      value "COLLABORATOR", "Author has been invited to collaborate on the repository.", value: :collaborator
      value "CONTRIBUTOR", "Author has previously committed to the repository.", value: :contributor
      value "FIRST_TIME_CONTRIBUTOR", "Author has not previously committed to the repository.", value: :first_time_contributor
      value "FIRST_TIMER", "Author has not previously committed to GitHub.", value: :first_timer
      value "NONE", "Author has no association with the repository.", value: :none
    end
  end
end
