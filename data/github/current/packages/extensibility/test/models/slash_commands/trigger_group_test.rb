# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class TriggerGroupTest < GitHub::TestCase
    context "#label" do
      test "uses a specified label when it exists" do
        group = SlashCommands::TriggerGroup.new(id: :actions)
        assert_equal "GitHub Actions", group.label
      end

      test "generates labels for categories that don't exist" do
        group = SlashCommands::TriggerGroup.new(id: :some_unknown_group)
        assert_equal "Some unknown group", group.label
      end
    end

    context "#sort_importance" do
      test "is based on key index" do
        group = SlashCommands::TriggerGroup.new(id: :actions)
        assert_equal 2, group.sort_importance
      end

      test "defaults to last place if group isn't defined" do
        last_place = SlashCommands::TriggerGroup::GROUP_LABELS.length
        group = SlashCommands::TriggerGroup.new(id: :some_unknown_group)
        assert_equal last_place, group.sort_importance
      end
    end
  end
end
