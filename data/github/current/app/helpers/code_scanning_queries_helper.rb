# typed: true
# frozen_string_literal: true

module CodeScanningQueriesHelper
  # Split 'array' into 'parts' arrays and return an array of those arrays, where
  # the sizes are as balanced as possible. If array.size < parts, only
  # array.size arrays are returned.
  def chunk(array, parts)
    parts = array.length if parts > array.length

    chunked = []
    parts.downto(1) do |i|
      chunked.push(array.slice!(0, (array.length.to_f / i).ceil))
    end

    chunked
  end

  # Returns an Azure client for the MRVA storage container.
  # This storage container is used for storing CodeQL databases, query packs,
  # instructions, and results for MRVA.
  def self.azure_client
    @azure_client ||= ::Azure::Storage::Blob::BlobService.create(
      storage_account_name: GitHub.codeql_variant_analysis_memory_alpha_key_id,
      storage_access_key: GitHub.codeql_variant_analysis_memory_alpha_access_key
    )
  end
end
