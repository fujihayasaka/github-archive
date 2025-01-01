# typed: true
# frozen_string_literal: true

module Storage
  # This policy defines how LFS files are stored and accessed using Memory Alpha.
  # Currently it is only used on Proxima.
  class LfsPolicy < Storage::MemoryAlphaPolicy
    extend T::Sig

    sig { params(url: String).returns(String) }
    def cdn_url(url)
      # We don't use Fastly in Proxima.
      url
    end

    def download_link
      now = Time.now
      sign = s3_sign.query(s3_credentials, "GET", @uploadable.storage_s3_key(self), @uploadable.storage_download_expiration.to_i)
      add_signed_query_params(sign)
      {
        href: sign.location,
        expires_at: sign.expires_at.xmlschema,
        expires_in: sign.expires.to_i
      }
    ensure
      stats_timing(:download, start: now) if now
    end

    protected

    def s3_sign
      LfsSign
    end

    private

    def s3_credentials
      {
         bucket: "git-lfs",
         key: GitHub.lfs_storage_account,
         secret: GitHub.lfs_access_key,
      }
    end
  end
end
