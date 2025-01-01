require_relative "../response"

module BlobOperations
  module Responses
    class GetBlob < BlobOperations::Response

      attr_reader :content, :oid, :size_bytes

      def initialize(client_response, content:, oid:, size_bytes:)
        super(client_response)
        @content = content
        @oid = oid
        @size_bytes = size_bytes
      end
    end
  end
end
