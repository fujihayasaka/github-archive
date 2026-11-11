# typed: true
# frozen_string_literal: true

module Codespaces
  class CacheSkus < Command
    def perform
      Codespaces::Vscs.targets.each do |vscs_target|
        api_url = Codespaces::VscsApiUrl.for_target(vscs_target)
        client = Codespaces::AnonymousVscsClient.new(api_url: api_url)

        # Use all regions even though they may not exist in the target environment because it preserves the functionality of
        # setting the cache to be an empty array for production-available regions that are not
        # available in other environments.
        Codespaces::Locations::Region.public.each do |region|
          if Codespaces::VscsServiceStamp.find(region:, vscs_target:).present?
            Codespaces::Skus::Cache.fetch_from_vscs(vscs_target, region.id, client)
          else
            Codespaces::Skus::Cache.set(vscs_target, region.id, [])
          end
        rescue => e
          if [:canary, :development, :latestdev, :latestppe, :latestprod].include?(vscs_target)
            # Canary, Dev and Latest-* are commonly unavailble due to development and testing
            # so exceptions are logged and ignored
            GitHub.logger.error({
              "exception" => e,
              "gh.codespaces.vscs_target" => vscs_target,
              "code.namespace" => "Codespaces::CacheSkus",
              "code.function" => "perform",
            })
          else
            raise
          end
        end
      end
    end
  end
end
