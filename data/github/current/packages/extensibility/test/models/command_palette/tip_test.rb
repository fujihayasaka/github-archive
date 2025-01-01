# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class TipTest < GitHub::TestCase
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @global_tip = build_tip(scope_types: [:global])
      @owner_tip = build_tip(scope_types: [:owner])
      @repository_tip = build_tip(scope_types: [:repository])
    end

    test "has scope_types" do
      assert_equal [""], @global_tip.scope_types
      assert_equal ["owner"], @owner_tip.scope_types
      assert_equal ["repository"], @repository_tip.scope_types
    end

    test "has prefix" do
      tip = build_tip(title: "to search pull requests", prefix: "#")
      assert_equal "#", tip.prefix
    end

    test "has title" do
      assert_equal "Type is:issue to filter to issues", @global_tip.title
    end

    test "has mode" do
      assert_equal "#", @global_tip.mode
    end

    test "only allows :global, :owner, :repository scope types" do
      assert_raises(Tip::UnknownScope, "Unknown scope type: invalid") do
        build_tip(scope_types: [:global, :owner, :repository, :invalid])
      end
    end

    test "allows multiples scopes" do
      tip = build_tip(scope_types: [:global, :owner, :repository])
      refute_empty tip.scope_types
    end

    def build_tip(title: "Type is:issue to filter to issues", scope_types: [:global], prefix: nil, mode: "#")
      Tip.new(title: title, scope_types: scope_types, prefix: prefix, mode: mode)
    end
  end
end
