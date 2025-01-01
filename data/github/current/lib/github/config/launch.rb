# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Launch
      # The twirp address of the deployer service.
      attr_reader :launch_deployer_twirp_address
      def launch_deployer_twirp_address=(val)
        @launch_deployer_twirp = nil
        @launch_deployer_twirp_address = val
      end

      # The HMAC signature secret for request verification.
      # This HMAC signature secret is specific to requests to the Deployer.
      attr_reader :launch_deployer_hmac_secret
      def launch_deployer_hmac_secret=(val)
        @launch_deployer = nil
        @launch_deployer_hmac_secret = val
      end

      # The twirp address of the deployer service in lab.
      attr_reader :launch_lab_deployer_twirp_address
      def launch_lab_deployer_twirp_address=(val)
        @launch_lab_deployer_twirp = nil
        @launch_lab_deployer_twirp_address = val
      end

      # The HMAC signature secret for request verification.
      # This HMAC signature secret is specific to requests to the Deployer in lab.
      attr_reader :launch_lab_deployer_hmac_secret
      def launch_lab_deployer_hmac_secret=(val)
        @launch_lab_deployer = nil
        @launch_lab_deployer_hmac_secret = val
      end

      # Public: The ID of the app where launch tokens should be associated.
      def launch_app_id
        @launch_app_id ||= OauthApplication.where(
          user_id: GitHub.trusted_oauth_apps_owner,
          name: ["GitHub Launch Deploy Button", "GitHub Launch"],
        ).pluck(:id).first
      end

      # Public: The GitHub App (Integration) that the Actions execution environment uses.
      #
      # This is used as part of the identifier for secrets in both prod and lab.
      def launch_github_app
        return nil unless GitHub.actions_enabled?
        @launch_github_app ||= Integration.where(
          owner_id: GitHub.trusted_oauth_apps_owner,
          name: launch_github_app_name,
        ).first
      end

      # Public: The name of the Actions GitHub App.
      def launch_github_app_name
        @launch_github_app_name ||= "GitHub Actions"
      end
      attr_writer :launch_github_app_name

      # Public: The ID of the GitHub App (Integration) that launch authenticates as in lab.
      def launch_lab_github_app
        return nil unless GitHub.actions_enabled?
        @launch_lab_github_app ||= Integration.where(
          owner_id: GitHub.trusted_oauth_apps_owner,
          name: launch_lab_github_app_name,
        ).first
      end

      # Public: The name of launch's GitHub App.
      def launch_lab_github_app_name
        @launch_lab_github_app_name ||= "GitHub Actions (lab)"
      end
      attr_writer :launch_lab_github_app_name

      # Where the PEM-encoded Launch CA certificates are stored.
      attr_accessor :launch_grpc_ca_certificates_path
    end
  end

  extend Config::Launch
end
