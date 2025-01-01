# typed: true
# frozen_string_literal: true

require "test_helper"

class OrcaTest < GitHub::TestCase
  context "#client" do
    test "initializes a new client with the configured base URL and HMAC key" do
      client = Orca.client

      assert_equal GitHub.orca_base_url, client.base_url
      assert_equal GitHub.orca_hmac_key, client.hmac_key
    end

    test "memoizes the client" do
      a = Orca.client
      b = Orca.client

      assert_same a, b
    end
  end
end
