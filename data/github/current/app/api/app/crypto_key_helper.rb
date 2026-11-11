# typed: false
# frozen_string_literal: true

require "diet_earthsmoke"

module Api::App::CryptoKeyHelper
  def generate_diet_earthsmoke_key_payload(name:, scope:)
    begin
      key = DietEarthsmoke::Key.new(name)
    rescue DietEarthsmoke::KeyParseError
      deliver_error! 500,
        message: "Unable to parse key material.",
        documentation_url: @documentation_url
    end

    version = key.current_key(scope: scope)

    encoded = Base64.strict_encode64(version.public_key)
    {
        key_identifier: version.id.to_s,
        key: encoded,
    }
  end

  def generate_vault_key_payload(name:, scope: "")
    key = JSON.parse(ENV[name])

    payload = key["versions"].map do |version, key_data|
      public_key = key_data["public_key"]

      key_identifier = if key_data["key_pair_algo"] == "LIBSODIUM-SEALED-BOX-CURVE25519-XSALSA20-POLY1305"
        version.to_i(16).to_s
      else
        Digest::SHA256.hexdigest(public_key)
      end

      out = {
        key_identifier: key_identifier,
        key: public_key,
        is_current: key["current"] == version,
      }

      if !scope.empty?
        out[:scope] = scope
      end

      out
    end

    payload
  end

  def deliver_vault_key(name:, feature_flag:, scope: "")
    deliver_error!(404) if GitHub.enterprise?

    if feature_flag
      feature_actor = if current_user.respond_to?(:integration)
        current_user.integration
      else
        current_user
      end

      deliver_error!(404) unless feature_actor
      deliver_error!(404) unless FeatureFlag.vexi.enabled?(feature_flag, feature_actor, default: false)
    end

    payload = generate_vault_key_payload(name: name, scope: scope)

    deliver_raw({ public_keys: payload })
  end
end
