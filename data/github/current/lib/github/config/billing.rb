# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Billing

      def azure_oauth_app_id
        @azure_oauth_app_id ||=
          ENV["BILLING_AZURE_PERMISSION_CHECK_OAUTH_APP_ID"].to_s
      end
      attr_writer :azure_oauth_app_id

      def azure_oauth_app_secret
        @azure_oauth_app_secret ||=
          ENV["GitHub_Subscription_Permission_Validation"].to_s
      end
      attr_writer :azure_oauth_app_secret

      def azure_oauth_app_redirect_uri_for_businesses
        @azure_oauth_app_redirect_uri_for_businesses ||=
          ENV["BILLING_AZURE_PERMISSION_CHECK_OAUTH_APP_REDIRECT_URI"].to_s
      end
      attr_writer :azure_oauth_app_redirect_uri_for_businesses

      def azure_oauth_app_redirect_uri_for_orgs
        @azure_oauth_app_redirect_uri_for_orgs ||=
          ENV["BILLING_AZURE_PERMISSION_CHECK_OAUTH_APP_REDIRECT_URI_FOR_ORGS"].to_s
      end
      attr_writer :azure_oauth_app_redirect_uri_for_orgs
    end
  end

  extend Config::Billing
end
