# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Export
    module BlobStorageService
      extend T::Helpers
      extend T::Sig
      interface!

      DEFAULT_EXPIRY = T.let(1.minute, ActiveSupport::Duration)

      class BlobServiceResponse < T::Struct
        extend T::Sig

        const :blob_url, T.nilable(String)
        const :blob_size, Integer
      end

      sig { params(scope: T.any(User, Business)).returns(T.all(BlobStorageService, Object)) }
      def self.get(scope)
        AzureBlobStorageService.new
      end

      sig { abstract.params(key: String, use_append_blob: T::Boolean).void }
      def create(key, use_append_blob = false); end

      sig { abstract.params(key: String, value: String, feature: String, use_append_blob: T::Boolean).void }
      def store(key, value, feature, use_append_blob = false); end

      sig { abstract.params(key: String, feature: String, filename: String, expiry: ActiveSupport::Duration).returns(T.nilable(BlobServiceResponse)) }
      def retrieve(key, feature, filename = "", expiry = DEFAULT_EXPIRY); end
    end
  end
end
