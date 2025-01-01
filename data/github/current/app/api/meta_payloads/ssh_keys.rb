# typed: true
# frozen_string_literal: true

class Api::MetaPayloads::SshKeys
  def self.key_from_environment(type)
    # This is separate for stubbing in tests.
    ENV["BABELD_SSH_PUBLIC_KEY_#{type.to_s.upcase}"]
  end

  def self.key_of_type(type)
    key = key_from_environment(type)
    return nil if key.nil?
    # A key has three space-separated components: algorithm, body, and comment.
    # Strip the comment and separate the first two by a single space, leaving
    # off a trailing newline.
    key.chomp.split(/\s+/)[0..1]&.join(" ")
  end

  def self.supported_keys
    [:ed25519, :ecdsa, :rsa].map { |type| key_of_type(type) }.compact
  end

  def self.payload
    if GitHub.multi_tenant_enterprise?
      # Proxima
      if FeatureFlag.vexi.enabled?(:ssh_keys_from_environment, default: false)
        self.supported_keys
      else
        []
      end
    elsif GitHub.enterprise?
      []
    else
      # dotcom
      if FeatureFlag.vexi.enabled?(:ssh_keys_from_environment, default: false)
        self.supported_keys
      else
        GitHub.ssh_host_keys
      end
    end
  end
end
