# typed: true
# frozen_string_literal: true

require "test_helper"

class BlackbirdSearch::RedisTest < GitHub::TestCase

  TEST_KEY = "test_key"

  AccessibleResources = Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources

  setup do
    BlackbirdSearch::Redis.set_sleep(false)
    BlackbirdSearch::Redis.del(keys: [TEST_KEY])
    @accessible_resources = AccessibleResources.new(
      accessible_private_repo_ids: [1],
      accessible_owner_ids: [2],
      authorized_organization_ids: [3],
      protected_organization_ids: [4],
    )
  end

  teardown do
    BlackbirdSearch::Redis.redis_instance.unstub
    BlackbirdSearch::Redis.del(keys: [TEST_KEY])
  end

  context "#key" do
    test "returns a formatted string with the provided arguments" do
      key_prefix = "v1"
      actor_id = 2
      session_id = "abc"
      ip_address = "127.0.0.1"
      assert_equal "#{key_prefix}:#{actor_id}:#{session_id}:#{ip_address}", BlackbirdSearch::Redis.key(key_prefix: key_prefix, actor_id: actor_id, session_id: session_id, ip_address: ip_address)
    end
  end

  context "#set" do
    test "returns result with true value if set is successful" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds).value!
      assert_equal @accessible_resources.to_h, AccessibleResources.decode(BlackbirdSearch::Redis.get(key: TEST_KEY).value!).to_h
    end

    test "is resilient to transient redis errors" do
      original = BlackbirdSearch::Redis.redis_instance
      BlackbirdSearch::Redis.stubs(:redis_instance).raises(::Redis::TimeoutError).then.returns(original)

      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds).value!
      assert_equal @accessible_resources.to_h, AccessibleResources.decode(BlackbirdSearch::Redis.get(key: TEST_KEY).value!).to_h
    end

    test "returns result with error if set exceeds retry limit" do
      ::Redis.any_instance.stubs(:set).raises(::Redis::ConnectionError)

      result = BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds)
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
      assert_nil BlackbirdSearch::Redis.get(key: TEST_KEY).value!
    end
  end

  context "#get" do
    test "returns result with value if get is successful" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds)
      assert_equal @accessible_resources.to_h, AccessibleResources.decode(BlackbirdSearch::Redis.get(key: TEST_KEY).value!).to_h
    end

    test "returns result with nil value if key does not exist" do
      assert_nil BlackbirdSearch::Redis.get(key: TEST_KEY).value!
    end

    test "is resilient to transient redis errors" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds).value!

      original = BlackbirdSearch::Redis.redis_instance
      BlackbirdSearch::Redis.stubs(:redis_instance).raises(::Redis::TimeoutError).then.returns(original)

      assert_equal @accessible_resources.to_h, AccessibleResources.decode(BlackbirdSearch::Redis.get(key: TEST_KEY).value!).to_h
    end

    test "returns result with error if get exceeds retry limit" do
      ::Redis.any_instance.stubs(:get).raises(::Redis::ConnectionError)

      result = BlackbirdSearch::Redis.get(key: TEST_KEY)
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
    end
  end

  context "#del" do
    test "returns result with number value of deleted keys if del is successful" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds)
      assert_equal 1, BlackbirdSearch::Redis.del(keys: [TEST_KEY]).value!
    end

    test "is resilient to transient redis errors" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds).value!

      original = BlackbirdSearch::Redis.redis_instance
      BlackbirdSearch::Redis.stubs(:redis_instance).raises(::Redis::TimeoutError).then.returns(original)

      assert_equal 1, BlackbirdSearch::Redis.del(keys: [TEST_KEY]).value!
    end

    test "returns result with error if del exceeds retry limit" do
      ::Redis.any_instance.stubs(:del).raises(::Redis::ConnectionError)
      result = BlackbirdSearch::Redis.del(keys: [TEST_KEY])
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
    end
  end

  context "#pttl" do
    test "returns number of milliseconds until the key expires" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds)
      assert_in_delta 10.seconds.to_i * 1000, BlackbirdSearch::Redis.pttl(key: TEST_KEY).value!, 1000
    end

    test "returns -2 if the key does not exist" do
      assert_equal -2, BlackbirdSearch::Redis.pttl(key: TEST_KEY).value!
    end

    test "is resilient to transient redis errors" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: @accessible_resources.to_proto, expire_sec: 10.seconds).value!

      original = BlackbirdSearch::Redis.redis_instance
      BlackbirdSearch::Redis.stubs(:redis_instance).raises(::Redis::TimeoutError).then.returns(original)

      assert_in_delta 10.seconds.to_i * 1000, BlackbirdSearch::Redis.pttl(key: TEST_KEY).value!, 1000
    end

    test "returns result with error if pttl exceeds retry limit" do
      ::Redis.any_instance.stubs(:pttl).raises(::Redis::ConnectionError)
      result = BlackbirdSearch::Redis.pttl(key: TEST_KEY)
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
    end
  end

  context "#at_indexing_limit?" do
    test "returns false if the actor has not reached the limit" do
      BlackbirdSearch::Redis.reset_indexing_limit(1)
      refute BlackbirdSearch::Redis.at_indexing_limit?(1)
    end

    test "sets expiration" do
      actor_id = 23
      BlackbirdSearch::Redis.reset_indexing_limit(actor_id)

      key = "#{BlackbirdSearch::Redis::INDEXING_LIMIT_KEY_PREFIX}:#{actor_id}"
      refute BlackbirdSearch::Redis.redis_instance.get(key)
      assert BlackbirdSearch::Redis.redis_instance.ttl(key) < 0
      refute BlackbirdSearch::Redis.at_indexing_limit?(actor_id)
      assert BlackbirdSearch::Redis.redis_instance.ttl(key) > 0
    end

    test "returns true if the actor has reached the limit" do
      actor_id = 2
      BlackbirdSearch::Redis.reset_indexing_limit(actor_id)
      refute BlackbirdSearch::Redis.at_indexing_limit?(actor_id, limit: 1)
      assert BlackbirdSearch::Redis.at_indexing_limit?(actor_id, limit: 1)
    end
  end

  context "#mutex" do
    test "return an instance of GitHub::Redis::ConcurrencySafeMutex" do
      assert_instance_of GitHub::Redis::ConcurrencySafeMutex, BlackbirdSearch::Redis.mutex(key: TEST_KEY, timeout_sec: 1.second)
    end
  end
end
