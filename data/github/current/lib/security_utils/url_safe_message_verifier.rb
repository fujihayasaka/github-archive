# typed: true
# frozen_string_literal: true

module SecurityUtils
  class UrlSafeMessageVerifier < ActiveSupport::MessageVerifier
    def verify(signed_message)
      raise InvalidSignature if signed_message.blank?

      data, digest = signed_message.split("--")
      if data.present? && digest.present? && SecurityUtils.secure_compare(digest, generate_digest(data))
        @serializer.load(::Base64.urlsafe_decode64(data))
      else
        raise InvalidSignature
      end
    end

    def generate(value)
      data = ::Base64.urlsafe_encode64(@serializer.dump(value))
      "#{data}--#{generate_digest(data)}"
    end
  end
end
