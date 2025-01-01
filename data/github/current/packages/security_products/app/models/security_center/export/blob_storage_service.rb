# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Export
    module BlobStorageService
      extend T::Helpers
      interface!

      DEFAULT_EXPIRY = T.let(1.minute, ActiveSupport::Duration)
      FILE_EXPIRY = T.let(3.days, ActiveSupport::Duration)

      class BlobServiceResponse < T::Struct

        const :blob_url, T.nilable(String)
        const :blob_size, Integer
      end

      sig { returns(T.all(BlobStorageService, Object)) }
      def self.get
        AzureBlobStorageService.new
      end

      sig { abstract.params(key: String).void }
      def create(key); end

      sig { abstract.params(key: String, value: String, feature: String).void }
      def store(key, value, feature); end

      sig { abstract.params(key: String, feature: String, filename: String, expiry: ActiveSupport::Duration).returns(T.nilable(BlobServiceResponse)) }
      def retrieve(key, feature, filename = "", expiry = DEFAULT_EXPIRY); end
    end
  end
end
