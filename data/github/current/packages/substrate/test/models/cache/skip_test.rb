# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/cache"

class GitHubCacheSkipMixinTest < GitHub::TestCase
  setup do
    @cache = GitHub::Cache::Fake.new
    @cache.allow = /.*/
    @cache.set("x", "y")
  end

  test "doesn't skip gets by default" do
    assert !@cache.skip
    assert_equal "y", @cache.get("x")
  end

  test "doesn't skip async_gets by default" do
    assert !@cache.skip
    assert_equal "y", @cache.async_get("x").sync.value
  end

  test "doesn't skip get_multi by default" do
    assert_equal({ "x" => "y" }, @cache.get_multi(%w[a x]))
  end

  test "doesn't skip async_get_multi by default" do
    assert_equal({ "x" => "y" }, @cache.async_get_multi(%w[a x]).sync)
  end

  test "skips get calls on when skip is set true" do
    @cache.skip = true
    assert_nil @cache.get("x")
  end

  test "skips async_get calls on when skip is set true" do
    @cache.skip = true
    assert_equal false, @cache.async_get("x").sync.exist?
  end

  test "skips get_multi calls when skip is set true" do
    @cache.skip = true
    assert_equal({}, @cache.get_multi(%w[a x]))
  end

  test "skips async_get_multi calls when skip is set true" do
    @cache.skip = true
    assert_equal({}, @cache.async_get_multi(%w[a x]).sync)
  end
end
