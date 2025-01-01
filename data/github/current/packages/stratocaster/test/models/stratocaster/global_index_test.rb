# typed: true
# frozen_string_literal: true

require "test_helper"

class Stratocaster::GlobalIndexTest < GitHub::TestCase
  fixtures do
    @list = (0...10).map do |i|
      FactoryBot.create(:stratocaster_global_index, value: i, index_key: "jibboo", modified_at: i.minutes.ago)
    end
  end

  context ".purge" do
    test "purges all records matching key and value" do
      assert_equal 10, Stratocaster::GlobalIndex.count
      FactoryBot.create(:stratocaster_global_index, value: 25, index_key: "axilla")
      assert_equal 11, Stratocaster::GlobalIndex.count

      Stratocaster::GlobalIndex.purge(["axilla"], 25)

      assert_equal 10, Stratocaster::GlobalIndex.count
    end
  end

  context "values" do
    test "returns the :limit most recent values matching the key" do
      assert_same_elements [0, 1, 2], Stratocaster::GlobalIndex.values("jibboo", 3)
    end

    test "returns the :limit most recent values matching the key and age range" do
      # 2min - 8min will return 6 records
      # adding a limit of 3 will return the 3 most recent within that range
      assert_same_elements [2, 3, 4], Stratocaster::GlobalIndex.values("jibboo", 3, 2.minutes, 8.minutes)
    end
  end

  context ".clear_keys" do
    test "purges all records matching key" do
      assert_equal 10, Stratocaster::GlobalIndex.count

      Stratocaster::GlobalIndex.clear_keys(["jibboo"])

      assert_equal 0, Stratocaster::GlobalIndex.count
    end
  end
end
