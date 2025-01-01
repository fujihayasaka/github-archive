# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class JumpToPageNavigationProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @user = create(:user)
        @provider = build_provider(JumpToPageNavigationProvider, current_user: @user, scope: nil)
      end

      test "supports unscoped queries" do
        items = @provider.search(nil)
        assert_predicate items, :present?
        items.each do |result|
          assert_result_structure(result)
        end
      end
    end
  end
end
