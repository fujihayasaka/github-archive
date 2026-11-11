# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module Proxima
      extend T::Helpers

      # all Proxima stamps should be added to this list
      ALL_STAMPS = T.let(%w[
        staff-wus2-01
        prod-weu-01
        prod-sdc-01
        prod-ae-01
        prod-cus-01
        test-cnc-01
        prod-jpw-01
        prod-wus3-01
        test-krc-01
      ].freeze, T::Array[String])

      REGION_STATUS_URLS = T.let({
        "au" => "https://au.githubstatus.com/",
        "eu" => "https://eu.githubstatus.com/",
        "jp" => "https://jp.githubstatus.com/",
        "us" => "https://us.githubstatus.com/",
        "default" => "https://www.githubstatus.com/"
      }.freeze, T::Hash[String, String])

      STAMP_REGIONS = T.let({
        "prod-ae-01" => "au",
        "prod-cus-01" => "us",
        "prod-jpw-01" => "jp",
        "prod-sdc-01" => "eu",
        "prod-weu-01" => "eu",
        "staff-wus2-01" => "us",
        "prod-wus3-01" => "us"
      }.freeze, T::Hash[String, String])

      sig { params(stamp: String).returns(T::Boolean) }
      def self.valid_stamp?(stamp)
        ALL_STAMPS.include?(stamp)
      end

      # Return the current Proxima stamp, or nil if not in Proxima
      sig { returns(T.nilable(String)) }
      def self.current_stamp
        return @current_stamp if defined?(@current_stamp)
        if GitHub.multi_tenant_enterprise?
          @current_stamp = T.let(ENV.fetch("HEAVEN_DEPLOYED_ENV", ""), T.nilable(String))
        else
          @current_stamp = T.let(nil, T.nilable(String))
        end
      end

      # If we're not in Proxima, return "dotcom"
      sig { returns(String) }
      def self.current_stamp_or_dotcom
        return T.must(@current_stamp_or_dotcom) if defined?(@current_stamp_or_dotcom)
        T.must(@current_stamp_or_dotcom = T.let(current_stamp || "dotcom", T.nilable(String)))
      end

      sig { returns(String) }
      def self.status_url_for_stamp
        region = STAMP_REGIONS[self.current_stamp_or_dotcom] || "default"
        T.must(REGION_STATUS_URLS[region])
      end

      # For example: "EU", "AU", "US", etc
      sig { returns(T.nilable(String)) }
      def self.current_region_label
        if region = STAMP_REGIONS[self.current_stamp_or_dotcom]
          region.upcase
        end
      end
    end
  end

  # Note: there's no need to extend this into GitHub::Config.
end
