# typed: false
# frozen_string_literal: true

module Storage
  # This policy defines how files are stored and accessed using Memory Alpha.
  class MemoryAlphaPolicy < Storage::S3Policy
    # we only override cdn_url here so we can call memory_alpha_fastly_acceleration_bucket which
    # has an actor-based feature flag we need to use for testing. when we're done and ready to only
    # have repo-based feature flags, we can remove this method altogether.
    def cdn_url(url)
      # We don't use Fastly in Proxima, but the Fastly parsing code below will fail without something configured. As
      # such, let's simply bail out early
      return url if GitHub.multi_tenant_enterprise?

      GitHub.dogstats.increment("memoryalpha.uploadable.migration", tags: ["backend:ma", "method:cdn_url", "class:#{@uploadable.class.name}"])
      fastly_bucket = @uploadable.memory_alpha_fastly_acceleration_bucket(@actor, @repository)
      return url unless fastly_bucket

      parsed = Addressable::URI.parse(url)
      parsed.host = fastly_bucket
      parsed.to_s
    end

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
