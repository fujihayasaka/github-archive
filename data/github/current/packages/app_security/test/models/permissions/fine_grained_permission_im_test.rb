# typed: true
# frozen_string_literal: true

require "test_helper"

module Permissions
  class FineGrainedPermissionImTest < GitHub::TestCase
    context "validations" do
      test "action is required" do
        assert_raises_with_message(ArgumentError, "Invalid action") do
          fgp = FineGrainedPermissionIm.new("", target_type: "Repository")
        end
      end

      test "target type is required" do
        assert_raises_with_message(ArgumentError, "Invalid target type") do
          fgp = FineGrainedPermissionIm.new("my_action")
        end
      end

      test "valid target type is required" do
        assert_raises_with_message(ArgumentError, "Invalid target type") do
          fgp = FineGrainedPermissionIm.new("my_action", target_type: "RandomTargetType")
        end
      end

      test "all actions are unique" do
        duplicate_actions = []
        FineGrainedPermissionIm.all.group_by(&:action).each do |action, fgps|
          if fgps.size > 1
            duplicate_actions << action
          end
        end
        assert duplicate_actions.empty?, "Duplicate actions registered with Permissions::FineGrainedPermissionIm: #{duplicate_actions.join(", ")}"
      end

    end

    context "self.all" do
      test "all fine grained permissions are valid" do
        skip # todo
      end
    end

    context "self.where" do
      test "preserves ordering of provided actions" do
        skip # todo
      end

      test "returns everything if passed no arguments" do
        skip # todo
      end
    end

    context "self.find" do
      # todo
    end
  end
end
