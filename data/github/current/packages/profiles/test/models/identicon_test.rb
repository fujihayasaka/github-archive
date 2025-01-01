# typed: true
# frozen_string_literal: true

require "test_helper"

class IdenticonTest < GitHub::TestCase
  context ".hash" do
    test "returns a 40-character string" do
      result = Identicon.generate_hash

      assert_instance_of String, result
      if GitHub.fips_mode?
        assert_equal 64, result.length
      else
        assert_equal 40, result.length
      end
    end

    test "uses the given seed to return a constant string" do
      seed = "some value"
      result1 = Identicon.generate_hash(seed)
      result2 = Identicon.generate_hash(seed)
      result3 = Identicon.generate_hash(seed)

      assert_equal result1, result2
      assert_equal result2, result3
    end

    test "uses a random seed when none is specified" do
      result1 = Identicon.generate_hash
      result2 = Identicon.generate_hash
      result3 = Identicon.generate_hash

      refute_equal result1, result2
      refute_equal result2, result3
    end
  end
end
