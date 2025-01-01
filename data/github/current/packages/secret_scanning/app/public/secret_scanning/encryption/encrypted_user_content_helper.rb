# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Encryption::EncryptedUserContentHelper
  extend T::Sig
  extend T::Helpers

  sig do
    params(
      content: T.nilable(String),
      content_id: T.nilable(Integer),
      content_created_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone))
    ).returns(T.nilable(String))
  end
  def self.encrypt_user_content(content, content_id, content_created_at)
    return nil unless content.present?
    unless content_id.present? && content_created_at.present?
      GitHub.dogstats.increment("secret_scanning.encrypted_user_content.encrypt", tags: ["success:false", "error:missing_id_or_created_at"])
      GitHub.logger.info(
        "Cannot encrypt user content since id or created_at are nil",
        "code.namespace": self.class.name,
        "code.function": "encrypt_user_content",
      )
      return nil
    end
    created_at = content_created_at.utc
    begin
      content = SecretScanning::Encryption::EncryptedUserContentCryptoHelper.encrypt_user_content(content, created_at, content_id)
      GitHub.dogstats.increment("secret_scanning.encrypted_user_content.encrypt", tags: ["success:true"])
      content
    rescue ArgumentError => e
      GitHub.dogstats.increment("secret_scanning.encrypted_user_content.encrypt", tags: ["success:false", "error:#{e.message}"])
      GitHub.logger.info(
        "Cannot encrypt user content due to an error",
        "code.namespace": self.class.name,
        "code.function": "encrypt_user_content",
        "exception.message": e.message,
      )
      nil
    end
  end
end
