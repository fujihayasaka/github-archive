# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamMembershipType < Platform::Enums::Base
      description "Defines which types of team members are included in the returned list. Can be one of IMMEDIATE, CHILD_TEAM or ALL."

      value "IMMEDIATE", "Includes only immediate members of the team.", value: "immediate"
      value "CHILD_TEAM", "Includes only child team members for the team.", value: "child_team"
      value "ALL", "Includes immediate and child team members for the team.", value: "all"
    end
  end
end
