# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Skus
    class Cache
      # Stores the SKUs that VSCS permits (fundamental to any availability in GH), and which other SKUs they can transition to.
      # This lets us avoid frequent API calls to validate that a SKU is permitted.
      # This cache is refreshed hourly by a background job.
      # Values are an array of hashes with shape { name: :sku1, transitions: [:sku2, :sku3] }.

      EXPIRY_HOURS = 24

      def self.key(vscs_target, location, vscs_target_url = nil)
        "codespaces.vscs_skus.#{vscs_target.to_sym}#{vscs_target_url.nil? ? "" : vscs_target_url}.#{location.downcase}"
      end

      def self.set(vscs_target, location, value, vscs_target_url = nil)
        cache_key = key(vscs_target, location, vscs_target_url)
        ActiveRecord::Base.connected_to(role: :writing) do
          Codespaces::Kv.store.set(cache_key, value.to_json, expires: EXPIRY_HOURS.hours.from_now)
        end
      end

      def self.get(vscs_target, location, vscs_target_url = nil, skip_location_validation: false)
        # Don't be case-sensitive regarding locations, as the VSCS API isn't.
        raise ArgumentError, "Invalid location '#{location}'" unless location && (skip_location_validation || Codespaces::Locations::Region.find(location).present?)
        raise ArgumentError, "Invalid vscs_target '#{vscs_target}'" unless vscs_target&.to_sym&.in?(GitHub::Config::VSCS_ENVIRONMENTS.keys)

        cache_key = key(vscs_target, location, vscs_target_url)
        value = Codespaces::Kv.store.get(cache_key).value { nil }
        if value
          GitHub::JSON.parse(value).map do |sku|
            sku["name"] = sku["name"].to_sym
            sku["transitions"] = sku["transitions"].map(&:to_sym)
            sku.symbolize_keys
          end
        else
          fetch_from_vscs(vscs_target, location, client = nil, vscs_target_url)
        end
      end

      def self.fetch_from_vscs(vscs_target, location, client = nil, vscs_target_url = nil)
        if vscs_target_url.nil?
          vscs_api_url = Codespaces::VscsApiUrl.new(vscs_target: vscs_target.to_sym, location: location).url
        else
          vscs_api_url = vscs_target_url
        end

        client ||= Codespaces::AnonymousVscsClient.new(api_url: vscs_api_url)
        begin
          response_json = client.get_json("api/v1/locations/#{location}")
          skus = (response_json["skus"] || []).map do |sku|
            {
              name: sku["name"].to_sym,
              transitions: (sku.dig("availableSettings", "sku") || []).map(&:to_sym)
            }
          end
          set(vscs_target, location, skus, vscs_target_url)
          skus
        rescue Codespaces::Client::BadResponseError, Codespaces::Client::ConnectionFailed => e
          []
        end
      end
    end
  end
end
