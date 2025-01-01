# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::EncryptedTokenTest < GitHub::TestCase
  context "#to_s" do
    test "returns token value" do
      value = "foo"
      assert_equal value, Copilot::EncryptedToken.new(value: value).to_s
    end
  end

  context "#decode_and_decrypt" do
    test "returns decoded and decrypted value" do
      encrypted_token = Copilot::EncryptedToken.from("foo")
      GitHub.expects(:decode_and_decrypt_capi_token).once.with("foo")
        .returns(Copilot::DecryptedToken.from("decoded decrypted value"))

      result = encrypted_token.decode_and_decrypt

      assert_instance_of Copilot::DecryptedToken, result
      assert_equal "decoded decrypted value", result.value
    end
  end

  context ".from" do
    test "wraps a token value in an EncryptedToken" do
      result = Copilot::EncryptedToken.from("foo")
      assert_instance_of Copilot::EncryptedToken, result
      assert_equal "foo", result.value
    end

    test "includes expiration time" do
      expiration = 1.minute.from_now
      result = Copilot::EncryptedToken.from("foo", expiration: expiration)
      assert_equal expiration, result.expiration
    end
  end

  context "#authorization_header_value" do
    test "includes necessary prefix for use in an Authorization header" do
      assert_equal "GitHub-Bearer foo", Copilot::EncryptedToken.new(value: "foo").authorization_header_value
    end
  end
end
