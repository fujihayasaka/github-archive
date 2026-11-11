# frozen_string_literal: true

GitHub::Application.configure do
  config.before_initialize do |app|
    if (fallback_secret = ENV["LEGACY_SECRET_KEY_BASE"]).present?
      app.message_verifiers.rotate(secret_key_base: fallback_secret)

      config.action_dispatch.cookies_rotations.tap do |cookies|
        encrypted_cookie_cipher = config.action_dispatch.encrypted_cookie_cipher || "aes-256-gcm"
        salt = config.action_dispatch.authenticated_encrypted_cookie_salt
        key_len = ActiveSupport::MessageEncryptor.key_len(encrypted_cookie_cipher)
        key_generator = ActiveSupport::KeyGenerator.new(fallback_secret, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256)
        cookies.rotate :encrypted, key_generator.generate_key(salt, key_len)
      end
    end
  end

  config.session_store :cookie_store,
    httponly: true,
    secure:   Rails.env == "test" ? false : GitHub.ssl?,
    key:      GitHub.session_key
end

WebAuthn.configure do |config|
  config.verify_attestation_statement = false
end
