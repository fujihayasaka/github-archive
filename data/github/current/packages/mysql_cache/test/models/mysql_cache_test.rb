# typed: true
# frozen_string_literal: true

require "test_helper"

class MysqlCacheTest < GitHub::TestCase
  include GitHub::LoggerHelper
  skip_enterprise
  skip_all_features

  setup do
    @redis_cache = ::MysqlCache.new
    @client = @redis_cache.redis_client
  end

  teardown do
  end

  fixtures do
    @some_user  = create(:user)
    @pub_repo   = create(:repository, owner: @some_user,  pushed_at: Time.now - 2.hours, from_example: :mojombo_grit)
  end


  context "with redis" do
    test "returns formatted key with passed in values" do
      time = Time.parse("2025-02-08T08:00Z").to_i # Saturday
      Time.stubs(:now).returns(time)
      assert_equal "ric-User-1-1739001600", @redis_cache.key(key_prefix: "ric", user_type: @some_user.type, repo_id: 1, set_time: time)
    end
  end

  context "redis get" do
    test "false when circuit is open" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(false)
      refute @redis_cache.set(key: "foo", value: "bar", expire_sec: 3)
      assert_nil @redis_cache.get(key: "foo")
    end

    test "returns set value" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(true)
      @redis_cache.set(key: "foo", value: "bar", expire_sec: 3)
      assert_equal "bar", @redis_cache.get(key: "foo")
    end
  end

  context "redis set" do
    test "sets the value" do
      assert_equal "OK", @redis_cache.set(key: "foo", value: 1, expire_sec: 3)
    end

    test "returns false when circuit is open" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(false)
      refute @redis_cache.set(key: "foo", value: 1)
    end
  end
end
