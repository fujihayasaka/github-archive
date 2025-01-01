# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ModeTest < GitHub::TestCase
    setup do
      @global_mode = build_mode
      @owner_mode = build_mode(scope_types: [:owner])
      @repository_mode = build_mode(scope_types: [:repository])
      @all_scopes_mode = build_mode(scope_types: [])
    end

    test "has scope_types" do
      assert_equal [""], @global_mode.scope_types
      assert_equal ["owner"], @owner_mode.scope_types
      assert_equal ["repository"], @repository_mode.scope_types
      assert_equal [], @all_scopes_mode.scope_types
    end

    test "has character" do
      assert_equal "#", @global_mode.character
    end

    test "has placeholder" do
      assert_equal "Search issues and pull requests", @global_mode.placeholder
    end

    test "only allows :global, :owner, :repository scope types" do
      assert_raises(Mode::UnknownScope, "Unknown scope type: invalid") do
        build_mode(scope_types: [:global, :owner, :repository, :invalid])
      end
    end

    test "allows multiples scopes" do
      mode = build_mode(scope_types: [:global, :owner, :repository])
      refute_empty mode.scope_types
    end

    test "allows empty scope types" do
      mode = build_mode(scope_types: [])
      assert_empty mode.scope_types
    end

    def build_mode(character: "#", placeholder: "Search issues and pull requests", scope_types: [:global])
      Mode.new(character: character, placeholder: placeholder, scope_types: scope_types)
    end
  end
end
