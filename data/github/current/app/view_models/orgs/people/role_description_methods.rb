# typed: true
# frozen_string_literal: true

module Orgs::People::RoleDescriptionMethods

  # Public: What does each role mean?
  #
  # Note that this is used for roles of existing organization membership
  # as well as for roles of pending organization invitations.
  #
  # Returns a string.
  def role_description
    case T.unsafe(self).role.type
    when :admin
      "Owners have full access to teams, settings, and repositories."
    when :direct_member
      "Members can be assigned to teams and collaborate on repositories."
    when :outside_collaborator
      "This person isn’t affiliated with the organization but has access to some of its repositories."
    when :suspended
      "A suspended member has been deprovisioned by an Identity Provider."
    when :reinstate
      "This person will have their member privileges reinstated if they join the organization."
    else
      "This person is not a member of the organization."
    end
  end
end
