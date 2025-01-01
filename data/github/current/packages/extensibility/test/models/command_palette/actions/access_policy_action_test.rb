# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/command_palette_action_tests"

module CommandPalette
  module Actions
    class AccessPolicyActionTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers
      include GitHub::CommandPaletteActionTests

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @action = AccessPolicyAction.new(path: urls.search_path(q: "french fries"))
        @type = AccessPolicyAction::TYPE
        @description = AccessPolicyAction::DESCRIPTION
      end
    end
  end
end
