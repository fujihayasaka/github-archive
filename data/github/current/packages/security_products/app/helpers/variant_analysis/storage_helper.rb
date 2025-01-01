# typed: true
# frozen_string_literal: true

module VariantAnalysis::StorageHelper
  include Kernel

  class InvalidBase64QueryPackError < StandardError; end
  class InvalidGzipQueryPackError < StandardError; end

  S3_CREDENTIALS = {
    bucket: GitHub.codeql_variant_analysis_memory_alpha_bucket,
    key: GitHub.codeql_variant_analysis_memory_alpha_key_id,
    secret: GitHub.codeql_variant_analysis_memory_alpha_access_key,
  }

  def upload_instructions_file(variant_analysis, content)
    path = instructions_file_path(variant_analysis.id)
    upload_content(path, content, "application/json")
    create_signed_url(path, 24.hours)
  end

  def upload_query_pack(variant_analysis, content)
    path = query_pack_path(variant_analysis.id)
    upload_content(path, content, "application/gzip")
    path
  end

  def create_signed_url(path, expiration)
    MemoryAlphaSign.query(S3_CREDENTIALS, "GET", path, expiration).location
  end

  def process_query_pack(query_pack)
    decoded = begin
      Base64.strict_decode64(query_pack)
    rescue ArgumentError
      raise InvalidBase64QueryPackError, "Could not decode query pack content. Expected Base64 encoded gzipped tarball."
    end

    unless is_query_pack_gzip?(decoded)
      raise InvalidGzipQueryPackError, "Query pack is not a valid gzip file"
    end

    decoded
  end

  def is_query_pack_gzip?(contents)
    contents.first(2).b == "\x1F\x8B".b
  end

  private

  def upload_content(path, content, content_type)
    CodeScanningQueriesHelper.azure_client.create_block_blob(
      GitHub.codeql_variant_analysis_azure_bucket,
      path,
      content,
      {
        content_type:,
      }
    )
  end

  def instructions_file_path(variant_analysis_id)
    "variant_analyses/#{variant_analysis_id}/instructions"
  end

  def query_pack_path(variant_analysis_id)
    "variant_analyses/#{variant_analysis_id}/query_pack"
  end
end
