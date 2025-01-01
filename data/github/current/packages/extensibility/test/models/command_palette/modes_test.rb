# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ModesTest < GitHub::TestCase
    test "has scope_types" do
      scope_types = Mode::SCOPES
        .map { |scope_type| scope_type == :global ? "" : scope_type }
        .map(&:to_s)

      Modes.all.each do |mode|
        if mode.scope_types.any?
          mode.scope_types.each do |scope_type|

            assert_includes scope_types, scope_type
          end
        else
          assert_equal [], mode.scope_types
        end
      end
    end

    test "has character" do
      Modes.all.each do |mode|
        refute_nil mode.character
      end
    end

    test "has placeholder" do
      Modes.all.each do |mode|
        refute_nil mode.placeholder
      end
    end

    context "#all_except_default" do
      test "returns modes except default" do
        modes = Modes.all_except_default

        assert_equal Modes.all.count - 1, modes.count
        modes.each do |mode|
          refute_nil mode
        end
      end
    end

    test "#mode" do
      Modes::MODES.keys.each do |key|
        refute_nil Modes.mode(key)
      end

      assert_nil Modes.mode(:invalid)
    end
  end
end
