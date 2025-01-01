# typed: true
# frozen_string_literal: true

require "azure/storage/blob"
require "azure/core"

module Storage

  # This policy extends the MemoryAlphaPolicy and overrides the `download_url` method.
  # The `download_url` method generates SAS URLs that directly target the ABS account
  # using SPN credentials with access to the ABS account.
  # Use this implementation to direct traffic to the ABS account, bypassing Memory Alpha when downloading.
  # Using the `MemoryAlphaPolicy`involves an additional round trip, as it returns a redirect to the
  # ABS account.

  # By default, if the `spn_*` methods are not defined on the `@uploadable` object, it will use the
  # global SPN credentials used by MA. If you configured an ABS account which gives access to the MA
  # SPN credentials, you can use the defaults.

  class MemoryAlphaWithDirectAbsDownloadPolicy < Storage::MemoryAlphaPolicy

    def azure_sign
      @azure_sign ||= AzureSign.new(@uploadable)
    end

    def using_cdn?(uploadable)
      return false if GitHub.multi_tenant_enterprise?
      uploadable.respond_to?(:storage_fastly_acceleration_bucket) && uploadable.storage_fastly_acceleration_bucket != nil
    end

    def download_url(_ = nil, expiration: nil)
      now = Time.now
      parsed = Addressable::URI.parse(azure_sign.base_url)
      signed_url = azure_sign.generate_signed_blob_url(:read, expiration)
      query = {}

      if using_cdn?(@uploadable)
        query = azure_sign.add_jwt_token_to_query(query, parsed.host)

        if @uploadable.respond_to?(:storage_azure_content_disposition) && @uploadable.storage_azure_content_disposition != nil
          query = azure_sign.add_content_disposition_to_query(query)
        end

        if @uploadable.respond_to?(:storage_download_content_type) && @uploadable.storage_download_content_type != nil
          query = azure_sign.add_content_type_to_query(query)
        end

        signed_url = cdn_url(signed_url, @uploadable)
      end

      query_string = "&#{query.to_query}" unless query.empty?
      unless query_string.to_s.empty?
        #Removing plus signs added in for spaces by to_query
        query_string = query_string.to_s.gsub("+", "%20") # Ensure spaces are encoded correctly
      end

      "#{signed_url}#{query_string}"
    ensure
      stats_timing(:download, start: now) if now
    end

    private

    # We need to override the cdn_url method to use the correct Fastly bucket for release assets.
    # This is because we're using a feature flag to determine whether or not the release assets are
    # using this policy, or the MemoryAlphaPolicy. Anytime this policy is used for release assets,
    # we need to force the use of the correct Fastly bucket since we're darkshipping the policy choice,
    # and multiple evaluations of the storage policy being used can result in errors.
    # This is a temporary solution until we can remove the MemoryAlphaPolicy for release assets.
    def cdn_url(url, uploadable)
      # We don't use Fastly in Proxima, but the Fastly parsing code below will fail without something configured. As
      # such, let's simply bail out early
      return url if GitHub.multi_tenant_enterprise?

      if uploadable.class.name == "ReleaseAsset"
        fastly_bucket = GitHub.release_assets_fastly_host
      else
        fastly_bucket = uploadable.storage_fastly_acceleration_bucket
      end

      return url unless fastly_bucket

      parsed = Addressable::URI.parse(url)
      parsed.host = fastly_bucket
      parsed.to_s
    end
  end
end
