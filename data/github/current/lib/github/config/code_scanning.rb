# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module CodeScanning

      # String URL of the turboscan service
      attr_accessor :turboscan_url
      # Sets the HMAC key used to authenticate with the turboscan service
      attr_accessor :turboscan_hmac_key
      # Sets S3 Bucket for uploading files for turboscan
      attr_accessor :turboscan_s3_bucket

      # Details for Azure Storage for turboscan
      attr_accessor :turboscan_azure_container
      attr_accessor :turboscan_azure_account_name
      attr_accessor :turboscan_azure_account_key
      attr_accessor :turboscan_azure_storage_dns_suffix

      def is_code_scanning_bot?(user)
        user && user.bot? && user.integration.id == Apps::Privileged::CodeScanning.id
      end


      attr_accessor :turboghas_url, :turboghas_hmac_key

      def dynamic_service_url(app_name, service_port, path, env: nil, service_name: nil, local_port: nil)
        environment_variable = env.present? ? env : "#{app_name.upcase}_URL"
        return ENV[environment_variable] if ENV[environment_variable].present?

        return "http://localhost:#{local_port || service_port}#{path}" if !Rails.env.production? || GitHub.single_tenant_enterprise?  # rubocop:disable GitHub/DoNotBranchOnRailsEnv

        if GitHub.multi_tenant_enterprise?
          stamp = ENV["HEAVEN_DEPLOYED_ENV"]
          if !GitHub.kube? && ENV["GH_CONSOLE"].present?
            # Since console hosts are not currently part of the service mesh, we override the URL to a non-Istio address for easier debugging.
            # This hack can be removed when non-Kubernetes hosts are added to the mesh, or the console hosts are moved to Kubernetes.
            return "https://#{app_name}.service.#{stamp}.github.net#{path}"
          else
            # Some apps may expose multiple services on a single Istio address
            # the service name should be provided to differentiate between them
            return "http://#{service_name || app_name}.#{app_name}-#{stamp}.svc.cluster.local:#{service_port}#{path}"
          end
        end

        "https://#{app_name}-production.service.iad.github.net#{path}"
      end
    end
  end

  extend Config::CodeScanning
end
