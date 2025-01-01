# typed: strict
# frozen_string_literal: true

require "test_helper"

class BlackbirdSearch::RedisTest < GitHub::TestCase

  TEST_KEY = "test_key"
  TEST_VALUE = "test_value"

  setup do
    BlackbirdSearch::Redis.del(keys: [TEST_KEY])
  end

  teardown do
    BlackbirdSearch::Redis.del(keys: [TEST_KEY])
  end

  context "#set" do
    test "returns result with true value if set is successful" do
      assert BlackbirdSearch::Redis.set(key: TEST_KEY, value: TEST_VALUE, expire_sec: 10.seconds).value!
      assert_equal TEST_VALUE, BlackbirdSearch::Redis.get(key: TEST_KEY).value!
    end

    test "returns result with error if set fails" do
      ::Redis.any_instance.stubs(:set).raises(::Redis::ConnectionError)

      result = BlackbirdSearch::Redis.set(key: TEST_KEY, value: TEST_VALUE, expire_sec: 10.seconds)
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
      assert_nil BlackbirdSearch::Redis.get(key: TEST_KEY).value!
    end
  end

  context "#get" do
    test "returns result with value if get is successful" do
      BlackbirdSearch::Redis.set(key: TEST_KEY, value: TEST_VALUE, expire_sec: 10.seconds)
      assert_equal TEST_VALUE, BlackbirdSearch::Redis.get(key: TEST_KEY).value!
    end

    test "returns result with nil value if key does not exist" do
      assert_nil BlackbirdSearch::Redis.get(key: TEST_KEY).value!
    end

    test "returns result with error if get fails" do
      ::Redis.any_instance.stubs(:get).raises(::Redis::ConnectionError)

      result = BlackbirdSearch::Redis.get(key: TEST_KEY)
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
    end
  end

  context "#del" do
    test "returns result with number value of deleted keys if del is successful" do
      BlackbirdSearch::Redis.set(key: TEST_KEY, value: TEST_VALUE, expire_sec: 10.seconds)
      assert_equal 1, BlackbirdSearch::Redis.del(keys: [TEST_KEY]).value!
    end

    test "returns result with error if del fails" do
      ::Redis.any_instance.stubs(:del).raises(::Redis::ConnectionError)
      result = BlackbirdSearch::Redis.del(keys: [TEST_KEY])
      refute result.ok?
      assert_instance_of ::Redis::ConnectionError, result.error
    end
  end

  context "#mutex" do
    test "return an instance of GitHub::Redis::ConcurrencySafeMutex" do
      assert_instance_of GitHub::Redis::ConcurrencySafeMutex, BlackbirdSearch::Redis.mutex(key: TEST_KEY, timeout_sec: 1.second)
    end
  end
end
