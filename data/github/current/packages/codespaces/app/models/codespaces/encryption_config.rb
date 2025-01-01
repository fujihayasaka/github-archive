# typed: true
# frozen_string_literal: true

module Codespaces
  class EncryptionConfig
    # This model expects the format of the ENV object to match the documentation here:
    # https://github.com/github/pse-architecture/blob/main/docs/adrs/0007-diet-earthsmoke-vault-json-format.md
    # and raises a validation error if not
    include ActiveModel::Validations
    include GitHub::Memoizer

    class InvalidEncryptionConfig < Codespaces::Error; end

    TOKEN_ENCRYPTION = "EARTHSMOKE_CODESPACES_TOKEN_ENCRYPTION_KEY"
    CONFIG_NAMES = [TOKEN_ENCRYPTION].freeze
    validates_presence_of :token_config, :keys, :symmetric_key, :current_key_version, :config_name, presence: true, message: "Invalid token config structure"
    validates :config_name, inclusion: { in: CONFIG_NAMES }

    attr_reader :config_name, :version

    def initialize(config_name, key_version: nil, raw_config: ENV[config_name])
      @config_name = config_name
      @raw_config = raw_config
      @version = key_version || current_key_version
      raise InvalidEncryptionConfig unless valid?
    end

    memoize def token_config
      @raw_config.present? ? JSON.parse(@raw_config) : nil
    end

    memoize def keys
      token_config&.dig("versions", version)
    end

    memoize def symmetric_key
      encoded_key = keys&.fetch("symmetric_key", nil)
      encoded_key.present? ? Base64.strict_decode64(encoded_key) : nil
    end

    private

    memoize def current_key_version
      token_config&.fetch("current", nil)
    end
  end
end
