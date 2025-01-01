# typed: true
# frozen_string_literal: true

module HostedComputeIms
  module Twirp
    autoload :BaseClient, "hosted_compute_ims/twirp/base_client"
    autoload :CuratedImagesClient, "hosted_compute_ims/twirp/ims_curated_images_client"
    autoload :CustomerImagesClient, "hosted_compute_ims/twirp/ims_customer_images_client"
    autoload :AdminClient, "hosted_compute_ims/twirp/ims_admin_client"
    autoload :NullClient, "hosted_compute_ims/twirp/null_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < Error; end
  end
end
