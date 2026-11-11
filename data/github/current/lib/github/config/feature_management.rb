# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module FeatureManagement
      # Set the name of the current stamp. If not set, returns dotcom.
      def set_feature_management_current_stamp
        @feature_management_current_stamp = GitHub.environment.fetch("FEATURE_MANAGEMENT_CURRENT_STAMP", "dotcom")
      end
      attr_accessor :feature_management_current_stamp

      # Set the HMAC key for the Feature Flag Hub (this is the Management API HMAC key)
      def set_feature_management_feature_flag_hub_mgmt_hmac_key
        @feature_management_feature_flag_hub_mgmt_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_MGMT_HMAC_KEY", nil)
      end
      attr_accessor :feature_management_feature_flag_hub_mgmt_hmac_key

      # Set the HMAC key for the Feature Flag Hub (this is the Checks API HMAC key)
      def set_feature_management_feature_flag_hub_checks_hmac_key
        @feature_management_feature_flag_hub_checks_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_CHECKS_HMAC_KEY", nil)
      end
      attr_accessor :feature_management_feature_flag_hub_checks_hmac_key

      # Set the Review lab HMAC key for the Feature Flag Hub (this is the staging-dotcom Checks API HMAC key)
      def set_feature_management_feature_flag_hub_checks_review_lab_hmac_key
        @feature_management_feature_flag_hub_checks_review_lab_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_CHECKS_REVIEW_LAB_HMAC_KEY", nil)
      end
      attr_accessor :feature_management_feature_flag_hub_checks_review_lab_hmac_key

      # Set the url key for the Feature Flag Hub
      def set_feature_management_feature_flag_hub_url
        url = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_URL", nil)
        if url.nil?
          if Rails.env.test?
            url = "https://fake-feature-flag-hub-url.github.com"
          end

          if GitHub.use_fm_lite?
            url = "http://localhost:8090/twirp"
          end

          if (Rails.env.production? || GitHub.employee_unicorn? || GitHub.review_lab? || GitHub.staff_host?) && !GitHub.enterprise?
            stamp = Proxima.current_stamp_or_dotcom
            if service_mesh_enabled?
              url = "http://feature-flag-hub.feature-flag-hub-#{stamp}.svc.cluster.local:8080/twirp"
            elsif stamp == "dotcom"
              url = "https://feature-flag-hub-dotcom.service.iad.github.net/twirp"
            else
              url = "https://feature-flag-hub-#{stamp}.service.#{stamp}.github.net/twirp"
            end
          end
        end
        @feature_management_feature_flag_hub_url = url
      end
      attr_accessor :feature_management_feature_flag_hub_url

      # Set the url key for Feature Flag Data
      def set_feature_management_feature_flag_data_url
        url = GitHub.environment.fetch("FEATURE_FLAG_DATA_URL", nil)
        if url.nil?
          if GitHub.use_fm_lite?
            url = "http://localhost:8090/twirp"
          end

          if Rails.env.production? && !GitHub.enterprise?
            stamp = Proxima.current_stamp_or_dotcom
            if service_mesh_enabled?
              url = "http://feature-flag-data.feature-flag-data-#{stamp}.svc.cluster.local:8010/twirp"
            elsif stamp == "dotcom"
              if GitHub.server_site == "gc-cus-02"
                url = "https://feature-flag-data-production.service.gc-cus-02.github.net/twirp"
              else
                url = "https://feature-flag-data-dotcom.service.iad.github.net/twirp"
              end
            else
              url = "https://feature-flag-data-#{stamp}.service.#{stamp}.github.net/twirp"
            end
          end
        end
        @feature_management_feature_flag_data_url = url
      end
      attr_accessor :feature_management_feature_flag_data_url

      # Set the HMAC key for the Feature Flag Data (this is the Checks API HMAC key)
      def set_feature_management_feature_flag_data_checks_hmac_shared_key
        @feature_management_feature_flag_data_checks_hmac_shared_key = GitHub.environment.fetch("FEATURE_FLAG_DATA_CHECKS_API_HMAC_SHARED_KEY", nil)
      end
      attr_accessor :feature_management_feature_flag_data_checks_hmac_shared_key

      # Should Vexi be using the Feature Management Lite backend?
      def use_fm_lite?
        return true if ENV["USE_FM_LITE"] == "1"
        return false if ENV["USE_FM_LITE"] == "0"
        return false if GitHub.single_tenant_enterprise?
        Rails.env.development?
      end

      # Should we enable the Devtools UI and load the /devtools/feature_flags routes?
      def devtools_feature_flags_ui_enabled?
        GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
      end
    end
  end

  extend Config::FeatureManagement
end
