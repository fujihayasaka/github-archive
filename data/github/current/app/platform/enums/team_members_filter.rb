# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamMembersFilter < Platform::Enums::Base
      description "Filters teams based on members. Can be one of ME or EMPTY."
      visibility :internal

      value "ME", "Includes teams that the viewer is a member of.", value: "me"
      value "EMPTY", "Includes teams that have no members.", value: "empty"
    end
  end
end
