# typed: false
# frozen_string_literal: true

module Storage
  # This policy defines how files are stored and accessed using Memory Alpha.
  class MemoryAlphaPolicy < Storage::S3Policy
    def upload_url
      GitHub.dogstats.increment("memoryalpha.uploadable.migration", tags: ["backend:ma", "method:upload_url", "class:#{@uploadable.class.name}"])
      b = @uploadable.storage_s3_bucket ? @uploadable.storage_s3_bucket : GitHub.s3_asset_bucket_name
      port = GitHub.memory_alpha_port ? ":#{GitHub.memory_alpha_port}" : ""
      "#{GitHub.memory_alpha_scheme}://#{GitHub.memory_alpha_host}#{port}/#{b}"
    end

    protected

    def s3_sign
      GitHub.dogstats.increment("memoryalpha.uploadable.migration", tags: ["backend:ma", "method:s3_sign", "class:#{@uploadable.class.name}"])
      MemoryAlphaSign
    end

    private

    def strip_bucket_name(url_path)
      parts = url_path.split("/")
      b = @uploadable.storage_s3_bucket ? @uploadable.storage_s3_bucket : GitHub.s3_asset_bucket_name

      last_part = ""
      (0..parts.length).each do |i|
        if last_part == b
          return parts[i..].join("/")
        end
        last_part = parts[i]
      end
      url_path
    end
  end
end
