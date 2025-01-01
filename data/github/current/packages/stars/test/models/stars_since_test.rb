# typed: true
# frozen_string_literal: true

require "test_helper"

class StarsSinceTest < GitHub::TestCase
  fixtures do
    @repo1 = create(:repository)
    @repo2 = create(:repository)
    create(:star, starrable: @repo1)
  end

  setup do
    @cache_key = StarsSince.new.send(:stars_since_cache_key, repository_id: @repo1.id, period: :daily)
  end

  context ".repository" do
    test "returns cached value when set" do
      Stars::Kv.store.set(@cache_key, "125")

      assert_equal StarsSince.repository(repository_id: @repo1.id), 125
    end

    test "sets the cache when value is not set" do
      assert_changes -> { Stars::Kv.store.exists(@cache_key).value! }, from: false, to: true do
        assert_equal StarsSince.repository(repository_id: @repo1.id), 1
      end
    end
  end

  context ".repositories" do
    test "returns cached value when set" do
      Stars::Kv.store.set(@cache_key, "125")

      counts = { @repo1.id => 125, @repo2.id => 0 }
      assert_equal counts, StarsSince.repositories(repository_ids: [@repo1.id, @repo2.id])
    end

    test "sets the cache when value is not set" do
      assert_changes -> { Stars::Kv.store.exists(@cache_key).value! }, from: false, to: true do
        counts = { @repo1.id => 1, @repo2.id => 0 }
        assert_equal counts, StarsSince.repositories(repository_ids: [@repo1.id, @repo2.id])
      end
    end
  end
end
