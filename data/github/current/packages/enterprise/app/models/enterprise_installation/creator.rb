# typed: true
# frozen_string_literal: true

class EnterpriseInstallation
  class Creator
    # inputs
    attr_reader :target, :actor, :server_id, :host_name, :http_only, :license_hash, :license_public_key, :public_key, :customer_name, :version, :entry_point
    # created during perform
    attr_reader :enterprise_installation, :integration, :integration_installation, :client_secret

    # Result from the EnterpriseInstallation creation
    class Result
      class Error < StandardError; end

      def self.success(enterprise_installation, client_secret) new(:success, enterprise_installation: enterprise_installation, client_secret: client_secret) end
      def self.failed(error) new(:failed, error: error) end

      attr_reader :error, :enterprise_installation, :client_secret

      def initialize(status, enterprise_installation: nil, client_secret: nil, error: nil)
        @status = status
        @enterprise_installation = enterprise_installation
        @error = error
        @client_secret = client_secret
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    # Public: Create an EnterpriseInstallation and required data for GitHub Connect
    #
    # target        - The Organization or Enterprise account that the EnterpriseInstallation is
    #                 being created for.
    # actor:        - The User performing the action.
    # server_data:  - Information provided by the server used to create the EnterpriseInstallation
    #
    # Returns an EnterpriseInstallation::Creator::Result.
    def self.perform(target, actor:, server_data:, entry_point:)
      new(target, actor: actor, server_data: server_data, entry_point: entry_point).perform
    end

    def initialize(target, actor: nil, server_data:, entry_point:)
      @target             = target
      @actor              = actor
      @server_id          = server_data["server_id"]
      @host_name          = server_data["host_name"]
      @http_only          = server_data["http_only"]
      @license_hash       = server_data["license_hash"]
      @license_public_key = server_data["license_public_key"]
      @public_key         = server_data["public_key"]
      @customer_name      = server_data["customer_name"]
      @version            = server_data["version"]
      @entry_point        = entry_point
    end

    def perform
      validate_actor_has_permission

      EnterpriseInstallation.transaction do
        create_enterprise_installation! # sets @enterprise_installation
        create_integration_on_target! # sets @integration & @client_secret
        create_integration_installation_on_target! # sets @integration_installation
      end

      Result.success(enterprise_installation, client_secret)
    rescue ActiveRecord::RecordInvalid => e
      Failbot.report(e)
      Result.failed e.record.errors.full_messages.to_sentence
    rescue Result::Error => e
      Failbot.report(e)
      Result.failed e.message
    end

    private

    def create_enterprise_installation!
      @enterprise_installation = target.enterprise_installations.create!(
        server_id: server_id,
        host_name: host_name,
        http_only: http_only,
        license_hash: license_hash,
        license_public_key: license_public_key,
        customer_name: customer_name,
        version: version,
      )
    end

    def create_integration_on_target!
      @integration, @client_secret = enterprise_installation.create_github_app(public_key, actor)
    end

    def create_integration_installation_on_target!
      repositories = target.is_a?(Organization) ? nil : :none
      installation_result = integration.install_on(
        target,
        repositories: repositories,
        installer: actor,
        entry_point: entry_point
      )

      raise Result::Error, "Failed to install #{integration.name} on #{target}" if installation_result.failed?
      @integration_installation = installation_result.installation
    end

    def validate_actor_has_permission
      return true if target.adminable_by?(actor)
      raise Result::Error, "Actor does not have permissions to create an EnterpriseInstallation on #{target.name}"
    end
  end
end
