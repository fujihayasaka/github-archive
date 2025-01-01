# typed: true
# frozen_string_literal: true

module HostedComputeIms
  module Twirp
    autoload :BaseClient, "hosted_compute_ims/twirp/base_client"
    autoload :CuratedImagesClient, "hosted_compute_ims/twirp/ims_curated_images_client"
    autoload :CustomerImagesClient, "hosted_compute_ims/twirp/ims_customer_images_client"
    autoload :AdminClient, "hosted_compute_ims/twirp/ims_admin_client"
    autoload :NullClient, "hosted_compute_ims/twirp/null_client"
    autoload :InternalClient, "hosted_compute_ims/twirp/ims_internal_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < Error; end

    sig { returns(AdminClient) }
    def self.admin_client
      @admin_client ||= AdminClient.new(base_url: GitHub.hosted_compute_ims_url_curated, hmac_key: GitHub.hosted_compute_ims_hmac_key)
    end

    sig { returns(CuratedImagesClient) }
    def self.curated_images_client
      if FeatureFlag.vexi.enabled?(:hosted_compute_ims_proxima_proxying_curated_images_enabled, default: false)
        @curated_images_client_proxima ||= CuratedImagesClient.new(base_url: GitHub.hosted_compute_ims_url_customer, hmac_key: GitHub.hosted_compute_ims_hmac_key) # customer URL resolves to the Proxima stamp URL
      else
        @curated_images_client_production ||= CuratedImagesClient.new(base_url: GitHub.hosted_compute_ims_url_curated, hmac_key: GitHub.hosted_compute_ims_hmac_key)
      end
    end

    sig { returns(CustomerImagesClient) }
    def self.customer_images_client
      @customer_images_client ||= CustomerImagesClient.new(base_url: GitHub.hosted_compute_ims_url_customer, hmac_key: GitHub.hosted_compute_ims_hmac_key)
    end

    sig { returns(InternalClient) }
    def self.internal_api_client
      @internal_api_client ||= InternalClient.new(base_url: GitHub.hosted_compute_ims_url_curated, hmac_key: GitHub.hosted_compute_ims_hmac_key)
    end
  end
end
