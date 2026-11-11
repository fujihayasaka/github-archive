# frozen_string_literal: true

module GitHub
  module LoadEncryptionKeys
    def self.load_keys_into_env
      keys = JSON.parse(File.read("#{Rails.root}/test/fixtures/encryption_keys.json"))
      keys.each do |key, value|
        ENV[key] = if value.is_a?(Hash)
          value.to_json
        else
          value.to_s
        end
      end
    end

    if Rails.env.development? && !GitHub.enterprise?
      load_keys_into_env
    end
  end
end
