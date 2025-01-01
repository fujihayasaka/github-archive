# typed: true
# frozen_string_literal: true

module GitHub
  module Qintel
    class Catalog
      PATH = "/files"

      attr_reader :credential_files

      # Fetch the credential file catalog from the Qintel API.
      #
      # client: - The Qintel::Client instance to use. For testing only.
      # path:   - The path to fetch. For testing only.
      #
      # Returns a Catalog instance.
      def self.fetch(client: Qintel.client, path: PATH)
        string_resp = client.get(path)

        begin
          parsed_resp = GitHub::JSON.load(string_resp)
        rescue Yajl::ParseError => e
          raise BadDataError, e.message
        end

        credential_files = parsed_resp.map { |h| CredentialFile.new(hash: h.symbolize_keys) }
        new(credential_files)
      end

      def initialize(credential_files)
        @credential_files = credential_files
      end
    end
  end
end
