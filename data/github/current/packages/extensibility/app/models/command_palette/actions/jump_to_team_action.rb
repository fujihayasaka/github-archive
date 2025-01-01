# typed: true
# frozen_string_literal: true

module CommandPalette
  module Actions
    class JumpToTeamAction < CommandPalette::Action
      TYPE = :jump_to_team
      DESCRIPTION = "Jump to"

      def initialize(path:)
        super(type: TYPE, description: DESCRIPTION, path: path)
      end
    end
  end
end
