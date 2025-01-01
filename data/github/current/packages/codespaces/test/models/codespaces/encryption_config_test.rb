# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesEncryptionConfigTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?
  end

  test "raises error if invalid config name passed" do
    assert_raises(Codespaces::EncryptionConfig::InvalidEncryptionConfig) do
      Codespaces::EncryptionConfig.new("invalid")
    end
  end

  test "doesn't raise error if valid config name passed" do
    Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION)
  end

  test "raises error if missing token_config" do
    assert_raises(Codespaces::EncryptionConfig::InvalidEncryptionConfig) do
      Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION, raw_config: nil)
    end
  end

  test "raises error if missing keys" do
    assert_raises(Codespaces::EncryptionConfig::InvalidEncryptionConfig) do
      Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION, raw_config: '{ "current": "banana", "versions": { "notbanana": {} } }')
    end
  end

  test "raises error if missing symmetric_key" do
    assert_raises(Codespaces::EncryptionConfig::InvalidEncryptionConfig) do
      Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION, raw_config: '{ "current": "banana", "versions": { "banana": { "wrongkey": "different" } } }')
    end
  end

  test "raises error if missing current_key_version" do
    assert_raises(Codespaces::EncryptionConfig::InvalidEncryptionConfig) do
      Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION, raw_config: "{}")
    end
  end
end
