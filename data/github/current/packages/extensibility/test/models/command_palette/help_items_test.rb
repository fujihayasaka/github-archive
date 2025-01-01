# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class HelpItemsTest < GitHub::TestCase
    test "has scope_types" do
      scope_types = HelpItem::SCOPES
        .map { |scope_type| scope_type == :global ? "" : scope_type }
        .map(&:to_s)

      HelpItems.all.each do |help_item|
        if help_item.scope_types.any?
          help_item.scope_types.each do |scope_type|

            assert_includes scope_types, scope_type
          end
        else
          assert_equal [], help_item.scope_types
        end
      end
    end

    test "has prefix" do
      HelpItems.all.each do |help_item|
        refute_nil help_item.prefix
      end
    end

    test "has title" do
      HelpItems.all.each do |help_item|
        refute_nil help_item.title
      end
    end
  end
end
