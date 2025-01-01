# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/command_palette_action_tests"

module CommandPalette
  module Actions
    class JumpToActionTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers
      include GitHub::CommandPaletteActionTests

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @example_search_path = urls.search_path(q: "french fries")
        @action = JumpToAction.new(path: @example_search_path)
        @type = JumpToAction::TYPE
        @description = JumpToAction::DESCRIPTION
      end
    end
  end
end
