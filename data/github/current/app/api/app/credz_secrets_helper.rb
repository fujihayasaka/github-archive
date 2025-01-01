# typed: true
# frozen_string_literal: true

module Api::App::CredzSecretsHelper
  extend T::Helpers
  requires_ancestor { Api::App }

  private

  def validate_result!(result)
    unless result
      Failbot.report(StandardError.new("no response from store_credential"), kredz: GitHub.kredz)
      deliver_error!(503, message: "Secrets unavailable. Please try again later.")
    end
  end

  def validate_storage!(result)
    unless result.stored
      Failbot.report(StandardError.new("store_credential did not store"), kredz: GitHub.kredz)
      deliver_error!(500, message: "Secret was not stored")
    end
  end

  def validate_listing!(result)
    unless result
      Failbot.report(StandardError.new("no response from list"), kredz: GitHub.kredz)
      deliver_error!(503, message: "Secrets unavailable. Please try again later.")
    end
  end

  def decrypt_enterprise_value(value)
    box = RbNaCl::Boxes::Sealed.from_private_key(Base64.decode64(GitHub.actions_secrets_private_key))
    box.decrypt(Base64.strict_decode64(value))
  end

  def pack_earthsmoke_value(key_name, key_identifier, value)
    begin
      value = Base64.strict_decode64(value)
    rescue ArgumentError
      deliver_error! 422,
        message: "Provided value is not a valid base64 value.",
        documentation_url: @documentation_url
    end

    begin
      key = DietEarthsmoke::Key.new(key_name).current_key

      earthsmoke_latest_key_identifier = key.id

      unless key_identifier == earthsmoke_latest_key_identifier.to_s
        deliver_error! 422,
          message: "Provided key `#{key_identifier}` is not the latest version available. Call `GET /secrets/public-key` and resign the data using the latest key.",
          documentation_url: @documentation_url
      end

      Secrets.embed(earthsmoke_latest_key_identifier, value)
    rescue DietEarthsmoke::KeyParseError
      deliver_error! 500,
          message: "Unable to parse key material.",
          documentation_url: @documentation_url
    end
  end

  def map_selected_repo_global_ids(credential)
    credential.selected_repositories.map do |repo|
      Platform::Helpers::NodeIdentification.from_global_id(repo.global_id)[1].to_s
    end
  end
end
