# typed: true
# frozen_string_literal: true

require "test_helper"

class QueueTest < GitHub::TestCase

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @q = Spam::Queue.new("fuzzy_fuzzball")
  end

  context "Instance methods" do
    test "#drop_this removes a value if it's on the list and returns true" do
      @q.push("127.0.0.1")
      assert_difference("@q.size", -1) do
        assert @q.drop_this "127.0.0.1"
      end
      refute @q.is_member? "127.0.0.1"
    end

    test "#drop_this does nothing if the value is not on the list" do
      @q.push("44.33.22.11")
      refute @q.is_member? "127.0.0.1"
      assert_no_difference "@q.size" do
        refute @q.drop_this "127.0.0.1"
      end
    end

    test "#size returns zero when there are no entries" do
      assert_equal 0, @q.size
    end

    test "#size returns the number of entries on the queue" do
      3.times.each { |t| @q.push("127.0.0.#{t}") }
      assert_equal 3, @q.size
    end

    test "#is_member? correctly returns whether or not a value is in the list" do
      @q.push("127.0.0.1")
      assert @q.is_member? "127.0.0.1"
      refute @q.is_member? "44.33.22.11"
    end

    test "#peek returns the correct entries" do
      5.times.each { |t| @q.push("127.0.0.#{t}") }
      assert_equal @q.peek(3), ["127.0.0.0", "127.0.0.1", "127.0.0.2"]
    end

    test "#peek returns empty array when there are no entries" do
      assert_equal @q.peek(3), []
    end

    test "#push adds a value to the entries" do
      refute @q.is_member? "127.0.0.1"
      @q.push("127.0.0.1")
      assert @q.is_member? "127.0.0.1"
    end

    test "#push does not add a value if it's already on the list" do
      @q.push("127.0.0.1")
      assert_no_difference "@q.size" do
        @q.push("127.0.0.1")
      end
    end
  end
end
