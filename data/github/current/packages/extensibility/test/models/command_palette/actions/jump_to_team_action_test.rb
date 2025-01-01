# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/command_palette_action_tests"

module CommandPalette
  module Actions
    class JumpToTeamActionTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers
      include GitHub::CommandPaletteActionTests

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @example_search_path = urls.search_path(q: "french fries")
        @action = JumpToTeamAction.new(path: @example_search_path)
        @type = JumpToTeamAction::TYPE
        @description = JumpToTeamAction::DESCRIPTION
      end
    end
  end
end
