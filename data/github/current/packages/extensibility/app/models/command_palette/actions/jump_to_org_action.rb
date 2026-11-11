# typed: true
# frozen_string_literal: true

module CommandPalette
  module Actions
    class JumpToOrgAction < CommandPalette::Action
      TYPE = :jump_to_org
      DESCRIPTION = "Jump to"

      def initialize(path:)
        super(type: TYPE, description: DESCRIPTION, path: path)
      end
    end
  end
end
