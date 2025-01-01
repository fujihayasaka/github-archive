# typed: strict
# frozen_string_literal: true

# Superclass for Codespaces APIs using HMAC
class Api::Internal::Codespaces::Hmac < Api::Internal
  sig { returns(T::Array[String]) }
  def self.request_hmac_keys
    GitHub.api_internal_codespaces_vscs_hmac_keys
  end

  sig { params(vscs_target: T.nilable(Symbol)).void }
  def authorize_vscs_target!(vscs_target)
    deliver_error!(403) unless valid_environments_from_hmac_key.include?(vscs_target)
  end

  sig { returns(T::Boolean) }
  def externally_accessible?
    true
  end

  sig { returns(T::Boolean) }
  def require_request_hmac?
    true
  end

  private

  sig { returns(T::Array[String]) }
  def production_hmac_keys
    GitHub.api_internal_codespaces_vscs_production_hmac_keys
  end

  sig { returns(T::Array[String]) }
  def ppe_hmac_keys
    GitHub.api_internal_codespaces_vscs_ppe_hmac_keys
  end

  sig { returns(T::Array[String]) }
  def development_hmac_keys
    GitHub.api_internal_codespaces_vscs_development_hmac_keys
  end

  sig { returns(T::Array[String]) }
  def valid_environments_from_hmac_key
    allowed_environments_from_hmac_key(production_hmac_keys, ppe_hmac_keys, development_hmac_keys)
  end

  sig { params(production_hmac_keys: T::Array[String], ppe_hmac_keys: T::Array[String], development_hmac_keys: T::Array[String]).returns(T::Array[String]) }
  def allowed_environments_from_hmac_key(production_hmac_keys, ppe_hmac_keys, development_hmac_keys)
    # Determine allowed environments from used HMAC key?
    authenticated_hmac_key = env[:request_hmac_key]
    allowed_environments_from_hmac_key ||= []
    if authenticated_hmac_key.in?(production_hmac_keys)
      allowed_environments_from_hmac_key << :production
      allowed_environments_from_hmac_key << :latestprod
    end
    if authenticated_hmac_key.in?(ppe_hmac_keys)
      allowed_environments_from_hmac_key << :ppe
      allowed_environments_from_hmac_key << :latestppe
    end
    if authenticated_hmac_key.in?(development_hmac_keys)
      allowed_environments_from_hmac_key << :development
      allowed_environments_from_hmac_key << :latestdev
      allowed_environments_from_hmac_key << :local
    end
    allowed_environments_from_hmac_key
  end
end
