# typed: true
# frozen_string_literal: true

require "test_helper"
require "set"

class SiteAvailableHandlesManagerTest < GitHub::TestCase

  context "#new" do

    test "creates AvailableHandlesManager instance" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)

      assert_equal available_handles_manager.class, Site::AvailableHandlesManager
      assert_equal available_handles_manager.approved_handles, stubbed_approved_handles
      assert_equal available_handles_manager.all_handles, Set.new(stubbed_approved_handles)
      assert_equal available_handles_manager.available_handles, stubbed_approved_handles
      assert_empty available_handles_manager.used_handles
    end

    test "creates AvailableHandlesManager instance with case specific handles" do
      stubbed_handles = %w[one zero minus_one]
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(handles: stubbed_handles, approved_handles: stubbed_approved_handles, shuffle_approved: false)

      assert_equal available_handles_manager.class, Site::AvailableHandlesManager
      assert_equal available_handles_manager.approved_handles, stubbed_approved_handles
      assert_equal available_handles_manager.all_handles, Set.new(stubbed_approved_handles).merge(stubbed_handles)
      assert_equal available_handles_manager.available_handles, stubbed_approved_handles
      assert_empty available_handles_manager.used_handles
    end
  end

  context ".use" do
    test "returns first available handle from the approved handles list" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle = available_handles_manager.use

      assert_equal handle, "one"
      assert_equal available_handles_manager.available_handles, %w[two three]
      assert_equal available_handles_manager.used_handles, Set.new(["one"])
    end

    test "available_handles list regenerates after all available handles are used" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle_1 = available_handles_manager.use
      handle_2 = available_handles_manager.use
      handle_3 = available_handles_manager.use
      handle_4 = available_handles_manager.use

      assert_equal handle_1, "one"
      assert_equal handle_2, "two"
      assert_equal handle_3, "three"
      assert_equal handle_4, "one"
      assert_equal available_handles_manager.available_handles, %w[two three]
      assert_equal available_handles_manager.used_handles, Set.new(%w[one two three])
    end

    test "returns requested handle if it exist in the approved handles list" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle = available_handles_manager.use("two")

      assert_equal handle, "two"
      assert_equal available_handles_manager.available_handles, %w[one three]
      assert_equal available_handles_manager.used_handles, Set.new(["two"])
    end

    test "returns requested handle if it is already used" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle_1 = available_handles_manager.use("two")
      handle_2 = available_handles_manager.use("two")

      assert_equal handle_1, "two"
      assert_equal handle_2, "two"
      assert_equal available_handles_manager.available_handles, %w[one three]
      assert_equal available_handles_manager.used_handles, Set.new(["two"])
    end

    test "returns first available handle if requested handle is not on the list" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle = available_handles_manager.use("four")

      assert_equal handle, "one"
      assert_equal available_handles_manager.available_handles, %w[two three]
      assert_equal available_handles_manager.used_handles, Set.new(["one"])
    end

    test "returns the same assigned handle for the same unavailable requested handle" do
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle_1 = available_handles_manager.use("four")
      handle_2 = available_handles_manager.use("five")
      handle_3 = available_handles_manager.use("four")

      assert_equal handle_1, "one"
      assert_equal handle_2, "two"
      assert_equal handle_3, "one"
      assert_equal available_handles_manager.available_handles, ["three"]
      assert_equal available_handles_manager.used_handles, Set.new(%w[one two])
    end

    test "returns requested handle if requested handle is within merged handles list" do
      stubbed_handles = %w[one zero minus_one]
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(handles: stubbed_handles, approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle = available_handles_manager.use("zero")

      assert_equal handle, "zero"
      assert_equal available_handles_manager.available_handles, %w[one two three]
      assert_equal available_handles_manager.used_handles, Set.new(["zero"])
    end

    test "returns first available handle if requested handle is not within merged handles list" do
      stubbed_handles = %w[one zero minus_one]
      stubbed_approved_handles = %w[one two three]
      available_handles_manager = Site::AvailableHandlesManager.new(handles: stubbed_handles, approved_handles: stubbed_approved_handles, shuffle_approved: false)
      handle = available_handles_manager.use("minus_two")

      assert_equal handle, "one"
      assert_equal available_handles_manager.available_handles, %w[two three]
      assert_equal available_handles_manager.used_handles, Set.new(["one"])
    end
  end
end
