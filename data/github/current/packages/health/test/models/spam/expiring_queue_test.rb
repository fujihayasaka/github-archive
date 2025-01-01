# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamExpiringQueueTest < GitHub::TestCase

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @q = Spam::ExpiringQueue.new("the-gumbo-train", 30)
    @item = "harpua"
  end

  context "#item_key" do
    test "it uses the prefix and item name" do
      key = @q.item_key(@item)
      assert_equal key, "the-gumbo-trainharpua"
    end
  end

  context "#set" do
    test "it also sets the value within Spam::Kv.store" do
      Timecop.freeze do
        key = @q.item_key(@item)

        @q.set(@item, 50)

        val = Spam::Kv.store.get(key).value!
        ttl = Spam::Kv.store.ttl(key).value!

        assert_equal(val, "50")
        assert_equal(ttl.to_i, 30.seconds.from_now.to_time.to_i)
      end
    end
  end

  context "#get" do
    test "it gets the values stored" do
      Timecop.freeze do
        key = @q.item_key(@item)

        @q.set(@item, 50)

        val = @q.get(@item)

        assert_equal(val, "50")
      end
    end
  end
end
