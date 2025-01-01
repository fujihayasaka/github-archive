# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class HelpItemTest < GitHub::TestCase
    setup do
      @global_help_item = build_help_item
      @owner_help_item = build_help_item(scope_types: [:owner])
      @repository_help_item = build_help_item(scope_types: [:repository])
      @all_scopes_help_item = build_help_item(scope_types: [])
    end

    test "has scope_types" do
      assert_equal [""], @global_help_item.scope_types
      assert_equal ["owner"], @owner_help_item.scope_types
      assert_equal ["repository"], @repository_help_item.scope_types
      assert_equal [], @all_scopes_help_item.scope_types
    end

    test "has a group" do
      assert_equal :modes_help, @global_help_item.group
    end

    test "has prefix" do
      assert_equal "#", @global_help_item.prefix
    end

    test "has hint" do
      assert_equal "#", @global_help_item.hint
    end

    test "has title" do
      assert_equal "Search issues and pull requests", @global_help_item.title
    end

    test "only allows :global, :owner, :repository scope types" do
      assert_raises(HelpItem::UnknownScope, "Unknown scope type: invalid") do
        build_help_item(scope_types: [:global, :owner, :repository, :invalid])
      end
    end

    test "allows multiples scopes" do
      help_item = build_help_item(scope_types: [:global, :owner, :repository])
      refute_empty help_item.scope_types
    end

    test "allows empty scope types" do
      help_item = build_help_item(scope_types: [])
      assert_empty help_item.scope_types
    end

    def build_help_item(title: "Search issues and pull requests", group: :modes_help, scope_types: [:global], prefix: "#")
      HelpItem.new(title: title, group: group, scope_types: scope_types, prefix: prefix)
    end
  end
end
