# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CollaboratorAffiliation < Platform::Enums::Base
      description "Collaborators affiliation level with a subject."

      value "OUTSIDE", "All outside collaborators of an organization-owned subject.", value: "outside"
      value "DIRECT", "All collaborators with permissions to an organization-owned subject, regardless of organization membership status.", value: "direct"
      value "ALL", "All collaborators the authenticated user can see.", value: "all"
    end
  end
end
