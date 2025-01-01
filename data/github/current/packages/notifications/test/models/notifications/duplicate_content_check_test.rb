# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsDuplicateContentCheckTest < GitHub::TestCase
  LOREM = "lorem ipsum dolor"

  context "#duplicate?" do
    test "returns false when content hasn't been seen before" do
      check = Notifications::DuplicateContentCheck.new(123)
      refute check.duplicate?(LOREM)
    end

    test "returns true if content has been seen before" do
      check = Notifications::DuplicateContentCheck.new(123)
      check.save LOREM
      assert check.duplicate?(LOREM)
    end

    test "returns false when the same content is checked for a different user" do
      first = Notifications::DuplicateContentCheck.new(123)
      first.save LOREM
      second = Notifications::DuplicateContentCheck.new(456)
      refute second.duplicate?(LOREM)
    end

    test "returns false when KV is unavailable" do
      check = Notifications::DuplicateContentCheck.new(123)
      Notifications::KV.store.stubs(:get).returns GitHub::Result.new { raise "boom" }
      refute check.duplicate?(LOREM)
    end

    test "returns false when a previously seen content has expired" do
      check = Notifications::DuplicateContentCheck.new(123)
      Timecop.freeze((1.day + Notifications::DuplicateContentCheck::EXPIRES).ago) do
        check.save(LOREM)
      end
      refute check.duplicate?(LOREM), "should not have seen expired key"
    end
  end

  context "#save" do
    test "marks content as having been seen" do
      check = Notifications::DuplicateContentCheck.new(123)
      refute check.duplicate?(LOREM)
      check.save(LOREM)
      assert check.duplicate?(LOREM)
    end

    test "fails silently when KV is unavailable" do
      Notifications::KV.store.expects(:set).raises(GitHub::KV::UnavailableError)
      check = Notifications::DuplicateContentCheck.new(123)
      check.save(LOREM)
      refute check.duplicate?(LOREM)
    end
  end

end
