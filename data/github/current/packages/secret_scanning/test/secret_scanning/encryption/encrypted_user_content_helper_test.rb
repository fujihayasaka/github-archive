# typed: true
# frozen_string_literal: true
require_relative "../../../../../test/test_helper"

class EncryptedUserContentHelperTest < GitHub::TestCase

  fixtures do
    @mock_iv = "123456789012"
    @mock_tag = "1234567890123456"

    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @issue = create(:issue, repository: @repo, title: "issue title", body: "issue body", user: @user)
  end

  context "encrypt_user_content" do
    test "successfully encrypts content" do
      ciphertext = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content(@issue.body, @issue.id, @issue.created_at)
      refute_nil ciphertext
      decrypted = SecretScanning::Encryption::EncryptedUserContentCryptoHelper.decrypt_encrypted_user_content(T.must(ciphertext), @issue.created_at.getutc, @issue.id)
      assert_equal decrypted, @issue.body
    end

    test "handles argument exception from crypto helpers" do
      SecretScanning::Encryption::EncryptedUserContentCryptoHelper.stubs(:try_get_encrypted_content_encryption_keys).raises(ArgumentError.new("Invalid argument"))
      content = SecretScanning::Encryption::EncryptedUserContentHelper.encrypt_user_content("content to encrypt", @issue.id, @issue.created_at)
      assert_nil content
    end
  end
end
