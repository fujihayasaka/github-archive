# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class TipsTest < GitHub::TestCase
    test "has scope_types" do
      scope_types = Tip::SCOPES
        .map { |scope_type| scope_type == :global ? "" : scope_type }
        .map(&:to_s)

      Tips.all.each do |help_item|
        refute help_item.scope_types.empty?

        help_item.scope_types.each do |scope_type|
          assert_includes scope_types, scope_type
        end
      end
    end

    test "has title" do
      Tips.all.each do |help_item|
        refute_nil help_item.title
      end
    end
  end
end
