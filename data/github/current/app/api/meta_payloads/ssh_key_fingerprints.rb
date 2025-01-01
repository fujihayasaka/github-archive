# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::SshKeyFingerprints
  def self.fingerprint_of_type(type)
    key = Api::MetaPayloads::SshKeys.key_of_type(type)
    return nil if key.nil?
    SSHData::PublicKey.parse(key)&.fingerprint
  end

  def self.supported_fingerprints
    [:ecdsa, :ed25519, :rsa].map do |type|
      ["SHA256_#{type.to_s.upcase}", fingerprint_of_type(type)]
    end.to_h.compact
  end

  def self.payload
    if GitHub.multi_tenant_enterprise?
      # Proxima
      if FeatureFlag.vexi.enabled?(:ssh_keys_from_environment, default: false)
        self.supported_fingerprints
      else
        {}
      end
    elsif GitHub.enterprise?
      {}
    else
      # dotcom
      if FeatureFlag.vexi.enabled?(:ssh_keys_from_environment, default: false)
        self.supported_fingerprints
      else
        GitHub.ssh_host_key_fingerprints
      end
    end
  end
end
