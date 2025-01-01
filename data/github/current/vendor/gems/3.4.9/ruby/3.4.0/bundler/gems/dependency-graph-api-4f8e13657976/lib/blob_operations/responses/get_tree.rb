require_relative "../response"

module BlobOperations
  module Responses
    class GetTree < BlobOperations::Response
      attr_reader :tree_entries

      def initialize(client_response, tree_entries:)
        super(client_response)
        @tree_entries = tree_entries
      end
    end

    class TreeEntry
      attr_reader :path, :mode, :oid

      def initialize(path:, mode: nil, oid:, repository_id: nil, blob_operations_provider: nil)
        @path = path
        @mode = mode
        @oid = oid
        @repository_id = repository_id
        @blob_operations_provider = blob_operations_provider
      end

      # Public: Shortcut method to call `get_blob` on `blob_operations_provider` with this repo and object ID
      #
      # Returns BlobOperations::Responses::GetBlob
      def get_blob!
        raise StandardError, "No blob_operations_provider" unless @blob_operations_provider.present?
        return @blob if defined?(@blob)

        @blob = @blob_operations_provider.get_blob(repository_id: @repository_id, oid: @oid)
      end
    end
  end
end
