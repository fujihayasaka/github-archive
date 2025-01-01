# typed: false
# frozen_string_literal: true

##
# Setup Aws::S3::Client with stuff from config/amazon_s3.yml
#
require "base64"
require "github"
require "aws-sdk-s3"
require "active_support/core_ext/hash"

module GitHub
  module Config
    # Mixed into the GitHub module. All methods defined here should be accessed
    # like GitHub.s3_primary_client.
    module S3
      def s3_environment_config
        @s3_environment_config ||= begin
          config = s3_configs[Rails.env].symbolize_keys
          config[:asset_bucket_name] ||= config[:bucket_name]
          config
        end
      end

      def s3_configs
        require "erb"
        require "yaml"
        @s3_configs ||= YAML.load(ERB.new(File.read("#{Rails.root}/config/amazon_s3.yml")).result)
      end

      # Public: Returns an S3 client for the "GitHub (Primary) AWS" account in
      # Okta. This account stores S3 objects for internal services.
      def s3_primary_client
        @s3_primary_client ||= Aws::S3::Client.new(
          access_key_id: s3_environment_config[:access_key_id],
          secret_access_key: s3_environment_config[:secret_access_key],
          region: "us-east-1")
      end

      # Public: Returns an S3 client for the "GitHub (Production Data) AWS"
      # account in Okta.
      def s3_enterprise_users_csv_client
        return s3_primary_client if Rails.env.development?

        @s3_enterprise_users_csv_client ||= Aws::S3::Client.new(
          access_key_id: s3_enterprise_users_csv_access_key,
          secret_access_key: s3_enterprise_users_csv_secret_key,
          region: "us-east-1")
      end

      # Public: Returns an S3 client for the "GitHub (Primary) AWS" account in
      # Okta with access to the github-billing-report-exports bucket. This account
      # stores S3 objects for internal services.
      def s3_metered_exports_client
        return s3_primary_client if Rails.env.development?

        @s3_metered_exports_client ||= Aws::S3::Client.new(
          access_key_id: s3_metered_exports_access_key,
          secret_access_key: s3_metered_exports_secret_key,
          region: "us-east-1")
      end

      def s3_metered_exports_bucket
        return s3_environment_config[:bucket_name] if Rails.env.development?

        "github-billing-report-exports"
      end

      # Public: Returns an S3 client for the TurboScan S3 bucket.
      # This is only used in Enterprise Server and local development.
      def s3_turboscan_client
        options = {
          force_path_style: s3_turboscan_custom_endpoint.present?,
          access_key_id: s3_turboscan_access_key,
          secret_access_key: s3_turboscan_secret_key,
          region: "us-east-1"
        }
        if s3_turboscan_custom_endpoint.present?
          options[:endpoint] = s3_turboscan_custom_endpoint
        end
        @s3_turboscan_client ||= Aws::S3::Client.new(options)
      end

      # If we're running in local development mode or on GitHub Enterprise we
      # can't use server-side encryption as it's not supported by Minio.
      def s3_turboscan_sse?
        s3_turboscan_custom_endpoint.blank?
      end

      # Public: Returns an S3 client for the "GitHub (Production Data) AWS"
      # account in Okta. This AWS account stores S3 objects related to user
      # facing features such as Releases, LFS, etc.
      def s3_production_data_client
        @s3_production_data_client ||= Aws::S3::Client.new(
          access_key_id: GitHub.s3_production_data_access_key,
          secret_access_key: GitHub.s3_production_data_secret_key,
          region: "us-east-1")
      end

      # Returns memory alpha client to be used instead of direct S3
      def memory_alpha_client(access_key_id, secret_access_key)
        @memory_alpha_client ||= Aws::S3::Client.new(
          endpoint: GitHub.memory_alpha_url,
          force_path_style: true,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
          region: "us-east-1")
      end

      # Public: Returns an S3 client for the "GitHub (Primary) AWS" account in
      # Okta with access to the github-compromised-credential-files bucket.
      #
      def s3_compromised_credential_files_client
        @s3_compromised_credential_files_client ||= Aws::S3::Encryption::Client.new(
          access_key_id: s3_compromised_credential_files_access_key,
          secret_access_key: s3_compromised_credential_files_secret_key,
          region: "us-east-1",
          encryption_key: s3_compromised_credential_files_encryption_key,
        )
      end

      # Should be a full URI, ending in a /, so an s3 key can be appended.
      #
      # ex: https://user-images.githubusercontent.com/
      def user_images_cdn_url
        @user_images_cdn_url ||= ENV["USER_IMAGES_CDN_URL"]
      end

      def user_images_cdn_url=(value)
        @user_images_cdn_url = value
      end

      # Should be a full URI, ending in a /, so an s3 key can be appended.
      #
      # ex: https://private-user-images.githubusercontent.com/
      def private_user_images_cdn_url
        @private_user_images_cdn_url ||= ENV["PRIVATE_USER_IMAGES_CDN_URL"]
      end

      def private_user_images_cdn_url=(value)
        @private_user_images_cdn_url = value
      end

      # Should be a full URI, ending in a /, so an s3 key can be appended.
      #
      # ex: https://secured-user-images.githubusercontent.com/
      def secured_user_images_cdn_url
        @secured_user_images_cdn_url ||= ENV["SECURED_USER_IMAGES_CDN_URL"]
      end

      def secured_user_images_cdn_url=(value)
        @secured_user_images_cdn_url = value
      end

      # Should be a full URI, ending in a /, so an s3 key can be appended.
      #
      # ex: https://marketplace-screenshots.githubusercontent.com/
      def marketplace_screenshots_cdn_url
        @marketplace_screenshots_cdn_url ||= ENV["MARKETPLACE_SCREENSHOTS_CDN_URL"]
      end

      def marketplace_screenshots_cdn_url=(value)
        @marketplace_screenshots_cdn_url = value
      end

      # Should be a full URI, ending in a /, so an s3 key can be appended.
      #
      # ex: https://marketplace-images.githubusercontent.com/
      def marketplace_images_cdn_url
        @marketplace_images_cdn_url ||= ENV["MARKETPLACE_IMAGES_CDN_URL"]
      end

      def marketplace_images_cdn_url=(value)
        @marketplace_images_cdn_url = value
      end

      def s3_packages_access_key
        ENV["PACKAGES_AWS_ACCESS_KEY"]
      end

      def s3_packages_secret_key
        ENV["PACKAGES_AWS_SECRET_KEY"]
      end

      def s3_packages_bucket
        ENV["PACKAGES_S3_BUCKET"]
      end

      # Should be a full URI, ending in a /, so an s3 key can be appended.
      #
      # ex: https://repository-images.githubusercontent.com/
      def repository_images_cdn_url
        @repository_images_cdn_url ||= ENV["REPOSITORY_IMAGES_CDN_URL"]
      end

      def repository_images_cdn_url=(value)
        @repository_images_cdn_url = value
      end

      def s3_production_data_access_key
        ENV["S3_PRODUCTION_DATA_ACCESS_KEY"]
      end

      def s3_production_data_secret_key
        ENV["S3_PRODUCTION_DATA_SECRET_KEY"]
      end

      def s3_enterprise_users_csv_access_key
        ENV["AWS_ACCESS_KEY_ID_GITHUB_PRODUCTION"]
      end

      def s3_enterprise_users_csv_secret_key
        ENV["AWS_SECRET_ACCESS_KEY_ID_GITHUB_PRODUCTION"]
      end

      def s3_enterprise_users_export_bucket
        return s3_environment_config[:bucket_name] if Rails.env.development?

        "github-enterprise-member-list-exports"
      end

      def s3_enterprise_dormant_users_export_bucket
        return "github-ghec-dormant-users-exports-dev" if Rails.env.development?

        "github-ghec-dormant-users-exports-prod"
      end

      def s3_org_members_export_bucket
        return "github-organization-members-exports-dev" if Rails.env.development?

        "github-organization-members-exports-prod"
      end

      def s3_metered_exports_access_key
        ENV["AWS_ACCESS_KEY_ID_GITHUB_PRODUCTION"]
      end

      def s3_metered_exports_secret_key
        ENV["AWS_SECRET_ACCESS_KEY_ID_GITHUB_PRODUCTION"]
      end

      def s3_turboscan_custom_endpoint
        return "http://localhost:9000" if Rails.env.development? && ENV["TURBOSCAN_S3_ENDPOINT"].nil?
        ENV["TURBOSCAN_S3_ENDPOINT"].presence
      end

      def s3_turboscan_access_key
        return "minio" if Rails.env.development? && ENV["AWS_ACCESS_KEY_ID_GITHUB_PRODUCTION"].nil?
        ENV["AWS_ACCESS_KEY_ID_GITHUB_PRODUCTION"]
      end

      def s3_turboscan_secret_key
        return "miniostorage" if Rails.env.development? && ENV["AWS_SECRET_ACCESS_KEY_ID_GITHUB_PRODUCTION"].nil?
        ENV["AWS_SECRET_ACCESS_KEY_ID_GITHUB_PRODUCTION"]
      end

      def s3_compromised_credential_files_access_key
        ENV["S3_COMPROMISED_CREDENTIAL_ACCESS_KEY_ID"]
      end

      def s3_compromised_credential_files_secret_key
        ENV["S3_COMPROMISED_CREDENTIAL_ACCESS_KEY_SECRET"]
      end

      # Loads the encryption key to be used with the encryption client
      def s3_compromised_credential_files_encryption_key
        Base64.decode64(ENV["S3_ENCRYPTION_KEY_GITHUB_COMPROMISED_CREDENTIAL_FILES"])
      end

      def s3_repository_file_new_bucket
        "github-#{Rails.env.downcase}-repository-file-5c1aeb"
      end

      def s3_repository_file_new_host
        "#{s3_repository_file_new_bucket}.s3.amazonaws.com"
      end

      def s3_upload_manifest_file_new_bucket
        "github-#{Rails.env.downcase}-upload-manifest-file-7fdce7"
      end

      def s3_upload_manifest_file_new_host
        "#{s3_upload_manifest_file_new_bucket}.s3.amazonaws.com"
      end

      def s3_user_asset_new_bucket
        "github-#{Rails.env.downcase}-user-asset-6210df"
      end

      def s3_user_asset_new_host
        "#{s3_user_asset_new_bucket}.s3.amazonaws.com"
      end

      attr_writer :s3_configs
    end
  end

  extend Config::S3
end
