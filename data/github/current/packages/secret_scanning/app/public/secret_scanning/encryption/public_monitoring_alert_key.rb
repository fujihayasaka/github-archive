# typed: strict
# frozen_string_literal: true

# Encrypts and decrypts opaque alert keys for public monitoring alerts.
#
# The alert key encodes `repository_id` and `alert_number` into an encrypted,
# URL-safe string so that the frontend never sees the raw values. This prevents
# leaking information about external repositories' secret scanning state.
#
# Uses SecretScanning::Encryption::CryptoHelper (AES-256-GCM) with the existing
# secret scanning transit keys managed via EncryptedSecretsCryptoHelper.
class SecretScanning::Encryption::PublicMonitoringAlertKey

  sig { params(repository_id: Integer, alert_number: Integer).returns(String) }
  def self.encrypt(repository_id, alert_number)
    payload = JSON.dump({ "r" => repository_id, "a" => alert_number })
    encrypted = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.encrypt_secret(payload)
    Base64.urlsafe_encode64(encrypted, padding: false)
  end

  sig { params(alert_key: String).returns(T::Hash[Symbol, Integer]) }
  def self.decrypt(alert_key)
    encrypted = Base64.urlsafe_decode64(alert_key)
    payload = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(encrypted)
    data = T.let(JSON.parse(payload), T::Hash[String, T.untyped])
    repository_id = Integer(data.fetch("r"))
    alert_number = Integer(data.fetch("a"))
    { repository_id: repository_id, alert_number: alert_number }
  end
end
