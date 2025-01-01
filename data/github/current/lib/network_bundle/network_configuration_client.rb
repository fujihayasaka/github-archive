# typed: true
# frozen_string_literal: true

module NetworkBundle
  class NetworkConfigurationsException < StandardError
    sig { params(error: NetworkServiceError).void }
    def initialize(error)
      @exception_type = exception
      @code = error.code
      super(error.message)
    end

    sig { returns(String) }
    attr_reader :code
  end

  class ComputeService < T::Enum
    enums do
      None = new
      Actions = new
      Codespaces = new
    end
  end

  class NetworkConfiguration
    sig { returns(String) }
    attr_accessor :name

    sig { returns(String) }
    attr_accessor :id

    sig { returns(ComputeService) }
    attr_accessor :compute_service

    sig { returns(String) }
    attr_accessor :service

    sig { returns(T::Array[T::Hash[String, Object]]) }
    attr_accessor :runner_groups

    sig { returns(T::Array[T::Hash[String, Object]]) }
    attr_accessor :compute_resources

    sig { returns(T::Array[NetworkSettingReference]) }
    attr_accessor :network_setting_references

    sig { returns(String) }
    attr_accessor :created_on
  end

  class ComputeResourceConfiguration
    sig { returns(String) }
    attr_accessor :id

    sig { returns(String) }
    attr_accessor :service

    sig { returns(ComputeResourceNetworkConfiguration) }
    attr_accessor :network_configuration

    def initialize(id:, service:, network_configuration:)
      @id = id
      @service = service
      @network_configuration = network_configuration
    end
  end

  class ComputeResourceNetworkConfiguration
    sig { returns(String) }
    attr_accessor :id

    sig { returns(T::Boolean) }
    attr_accessor :enabled

    sig { returns(T::Array[ComputeResourceNetworkResource]) }
    attr_accessor :network_resources

    def initialize(id:, enabled:, network_resources:)
      @id = id
      @enabled = enabled
      @network_resources = network_resources
    end
  end

  class ComputeResourceNetworkResource
    sig { returns(String) }
    attr_accessor :id

    sig { returns(String) }
    attr_accessor :name

    sig { returns(String) }
    attr_accessor :state

    sig { returns(String) }
    attr_accessor :location

    sig { returns(String) }
    attr_accessor :subnet_id

    def initialize(id:, name:, state:, location:, subnet_id:)
      @id = id
      @name = name
      @state = state
      @location = location
      @subnet_id = subnet_id
    end
  end

  class NetworkServiceError
    sig { returns(String) }
    attr_accessor :message

    sig { returns(String) }
    attr_accessor :code

    sig { params(message: String, code: String).void }
    def initialize(message, code)
      @message = message
      @code = code
    end
  end

  class NetworkSettingReference
    sig { returns(String) }
    attr_accessor :id

    def initialize(id:)
      @id = id
    end
  end

  class NetworkSettings
    sig { returns(String) }
    attr_accessor :id

    sig { returns(String) }
    attr_accessor :resource_id

    sig { returns(String) }
    attr_accessor :display_name

    sig { returns(String) }
    attr_accessor :location

    sig { returns(String) }
    attr_accessor :resource_group

    sig { returns(String) }
    attr_accessor :subnet_id

    sig { returns(String) }
    attr_accessor :subnet

    sig { returns(String) }
    attr_accessor :subscription

    sig { returns(String) }
    attr_accessor :virtual_network

    sig { returns(String) }
    attr_accessor :state

    sig { returns(String) }
    attr_accessor :resource_name

    sig { returns(String) }
    attr_accessor :network_configuration_id
  end

  class NetworkConfigurationClient
    # Name of the service in the catalog
    SERVICE_NAME = "cps-network-service"

    sig { params(service_url: String, hmac_secrets: String, verbose: T::Boolean).void }
    def initialize(service_url, hmac_secrets, verbose = false)
      @service_url = service_url
      @hmac_secrets = hmac_secrets
      @verbose = verbose
      @stamp_id = GitHub::CurrentTenant.get&.shortcode.to_s
    end

    sig { params(actor: T.untyped, verbose: T::Boolean).returns(NetworkBundle::NetworkConfigurationClient) }
    def self.create(actor: nil, verbose: false)
      if GitHub.enterprise?
        raise NetworkConfigurationsException.new(NetworkServiceError.new("Network configurations are not available on GitHub Enterprise", "NotAvailable"))
      end
      # Flip the `new` call back to using the `verbose` flag when the feature flag is removed
      if use_new_network_url?
        new(GitHub.cps_network_url, GitHub.cps_network_service_hmac_secrets, true)
      else
        new(GitHub.cps_network_service_url, GitHub.cps_network_service_hmac_secrets, true)
      end
    end

    # List network configurations
    # service: "actions" or "codespaces" filtering
    # resource_id: runner_group_id for runner group filtering
    # enabled: string instead of boolean otherwise it will be default filtering
    sig { params(actor: T.untyped, service: String, resource_id: String, enabled: T.nilable(T::Boolean), name: String).returns(T::Array[NetworkConfiguration]) }
    def list_configurations(actor, service = "", resource_id = "", enabled = nil, name = "")
      queries = {}
      queries["service"] = service unless service.empty?
      queries["resource"] = resource_id unless resource_id.empty?
      queries["enabled"] = enabled unless enabled.nil?
      queries["name"] = name unless name.empty?
      queries["sortBy"] = "nameAscending"
      result = client.get do |req|
        req.url "configurations", queries
        generate_header(req, actor.id.to_s)
        GitHub.logger.info({
          msg: "Listing network configurations",
          fn: "network_configuration_client.list_configurations",
          "gh.actor.id": actor.id
        }) if @verbose
      end

      if result.success?
        json_result = JSON.parse(result.body)
        if json_result.empty?
          network_configs = []
          error = get_response_error_message(result)
          GitHub.logger.error({
            msg: "failed to fetch network configurations, empty result",
            fn: "network_configuration_client.list",
            organization_id: actor.id,
            result_status: result.status,
            result_error: error.message })
        else
          network_configs = json_result["value"].map do |network_config|
            parse_network_configuration(network_config)
          end
        end
      else
        # When the service returns a persistent 500-level error, the Resilient
        # middleware will circuit-break and return a 502 with an empty body.
        network_configs = []
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to fetch network configurations",
          fn: "network_configuration_client.list",
          organization_id: actor.id,
          result_status: result.status,
          result_error: error.message })
        raise NetworkConfigurationsException.new(error)
      end
      network_configs
    end

    # Create or update network configuration
    # https://github.com/github/cps-network-service/blob/main/docs/ADRs/network-bundle-API.md#semantics
    sig { params(actor: T.untyped, network_setting_ids: T::Array[String], selected_service: T.nilable(ComputeService), name: String, configuration_id: String).returns(NetworkConfiguration) }
    def create_or_update_configuration(actor, network_setting_ids:, selected_service: nil, name: "", configuration_id: "")
      body = {}
      body[:name] = name if name.present?
      body[:id] = configuration_id if configuration_id.present?

      if selected_service.present?
        if selected_service == ComputeService::Actions
          body[:computeServices] = [{ name: "actions", enabled: true }]
        elsif selected_service == ComputeService::Codespaces
          body[:computeServices] = [{ name: "codespaces", enabled: true }]
        elsif selected_service == ComputeService::None
          body[:computeServices] = []
        end
      end

      body[:networkResources] = network_setting_ids.map do |id|
        {
          id: id,
          type: "networkSettings",
        }
      end

      body[:stampId] = @stamp_id if @stamp_id.present?

      result = client.put do |req|
        req.url "configurations"
        req.body = body.to_json
        generate_header(req, actor.id.to_s)
        req.headers["Content-Type"] = "application/json"
      end

      if result.success?
        json_result = JSON.parse(result.body)
        parse_network_configuration(json_result)
      else
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to create or update private networks",
          fn: "network_configuration_client.create_or_update",
          organization_id: actor.id,
          result_status: result.status,
          result_error: error.message })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Get configuration
    sig { params(actor: T.untyped, configuration_id: String).returns(NetworkConfiguration) }
    def get_configuration(actor, configuration_id)
      result = client.get do |req|
        req.url "configurations/#{configuration_id}"
        generate_header(req, actor.id.to_s)
      end
      if result.success?
        json_result = JSON.parse(result.body)
        parse_network_configuration(json_result)
      else
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to get network configuration",
          fn: "network_configuration_client.get",
          organization_id: actor.id,
          network_id: configuration_id,
          result_status: result.status,
          result_error: "#{error.message}; id: #{configuration_id}" })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Delete configuration
    sig { params(actor: T.untyped, configuration_id: String).void }
    def delete_configuration(actor, configuration_id)
      result = client.delete do |req|
        req.url "configurations/#{configuration_id}"
        generate_header(req, actor.id.to_s)
      end
      if !result.success?
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to delete network configuration",
          fn: "network_configuration_client.delete",
          organization_id: actor.id,
          network_id: configuration_id,
          result_status: result.status,
          result_error: "#{error.message}; id: #{configuration_id}" })
        raise NetworkConfigurationsException.new(error)
      end
    end

    sig { params(actor: T.untyped, configuration_id: String, service: String, resource_id: String, name: String).void }
    def configure_compute_resource(actor, configuration_id, service, resource_id, name)
      result = client.put do |req|
        req.url "configurations/#{configuration_id}/services/#{service}/resources"
        generate_header(req, actor.id.to_s)
        req.headers["Content-Type"] = "application/json"
        req.body = { id: resource_id, name: name }.to_json
      end
      if !result.success?
        error = get_response_error_message(result)
        GitHub.logger.error(
          "Failed to configure network configurations",
          "code.function" => "network_configuration_client.configure_compute_resource",
          "gh.org.id" => actor.id,
          "gh.hosted_compute_networking.network_id" => configuration_id,
          "gh.hosted_compute_networking.result_status" => result.status,
          "gh.hosted_compute_networking.result_error" => "#{error.message}; id: #{configuration_id}; resource_id: #{resource_id}"
        )
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Remove compute resource from network configuration
    sig { params(actor: T.untyped, configuration_id: String, service: String, resource_id: String).void }
    def remove_network_configuration_from_runner_group(actor, configuration_id, service, resource_id)
      result = client.delete do |req|
        req.url "configurations/#{configuration_id}/services/#{service}/resources/#{resource_id}"
        generate_header(req, actor.id.to_s)
      end
      if !result.success?
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to remove network configuration from runner group",
          fn: "network_configuration_client.remove_network_configuration_from_runner_group",
          organization_id: actor.id,
          network_id: configuration_id,
          result_status: result.status,
          result_error: "#{error.message}; id: #{configuration_id}; resource_id: #{resource_id}" })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Get details for the given compute resource
    sig { params(actor: T.untyped, service: String, resource_id: String).returns(T.nilable(ComputeResourceConfiguration)) }
    def get_compute_resources(actor, service, resource_id)
      result = client.get do |req|
        req.url "configurations/services/#{service}/computeResources/#{resource_id}"
        generate_header(req, actor.id.to_s)
      end
      if result.status == 404
        nil
      elsif result.success?
        json_result = JSON.parse(result.body)
        parse_compute_resources(json_result)
      else
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to get compute resources",
          fn: "network_configuration_client.get_compute_resources",
          organization_id: actor.id,
          resource_id: resource_id,
          result_status: result.status,
          result_error: "#{error.message}; id: #{resource_id}" })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Disable all network configurations for all given organization IDs
    sig { params(actor: T.untyped, entity_ids: T::Array[String]).void }
    def disable_organizations_configurations(actor, entity_ids)
      result = client.post do |req|
        req.url "configurations/organizations/services/disable"
        generate_header(req, actor.id.to_s)
        req.headers["Content-Type"] = "application/json"
        req.body = entity_ids.to_json
      end

      if !result.success?
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to disable network configurations",
          fn: "network_configuration_client.disable_all_configurations",
          enterprise_id: actor.id,
          result_status: result.status,
          result_error: error.message })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Get network settings with the given id
    sig { params(actor: T.untyped, settings_id: String).returns(NetworkSettings) }
    def get_settings(actor, settings_id)
      result = client.get do |req|
        req.url "settings/#{settings_id}"
        generate_header(req, actor.id.to_s)
      end

      if result.success?
        json_result = JSON.parse(result.body)
        parse_network_settings(json_result)
      else
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to fetch private network",
          fn: "network_configuration_client.get_settings",
          enterprise_id: actor.id,
          network_id: settings_id,
          result_status: result.status,
          result_error: error.message })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Register the given network settings
    sig { params(actor: T.untyped, settings_id: String).returns(NetworkSettings) }
    def register_settings(actor, settings_id)
      result = client.post do |req|
        req.url "settings/#{settings_id}/register"
        generate_header(req, actor.id.to_s)
      end

      if result.success?
        json_result = JSON.parse(result.body)
        parse_network_settings(json_result)
      else
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to register the private network",
          fn: "network_configuration_client.create_settings",
          enterprise_id: actor.id,
          network_id: settings_id,
          result_status: result.status,
          result_error: error.message })
        raise NetworkConfigurationsException.new(error)
      end
    end

    # Deregister the given network settings
    sig { params(actor: T.untyped, settings_id: String).void }
    def deregister_settings(actor, settings_id)
      result = client.post do |req|
        req.url "settings/#{settings_id}/deregister"
        generate_header(req, actor.id.to_s)
      end

      if !result.success?
        error = get_response_error_message(result)
        GitHub.logger.error({
          msg: "failed to deregister private network",
          fn: "network_configuration_client.deregister_settings",
          enterprise_id: actor.id,
          network_id: settings_id,
          result_status: result.status,
          result_error: error.message })
        raise NetworkConfigurationsException.new(error)
      end
    end

    def self.use_new_network_url?
      FeatureFlag.vexi.enabled?("cps_network_service_new_url", default: false)
    end

    private

    sig { returns(Faraday::Connection) }
    def client
      return @client if @client
      GitHub.logger.info({
        msg: "Creating network configuration Farday client to '#{@service_url}'",
        fn: "network_configuration_client.client",
      }) if @verbose
      @client = GitHub::FaradayClient.internal(SERVICE_NAME, @service_url, {
        request: {
          open_timeout: 1, # seconds
          timeout: 2,      # seconds
        }
      }) do |conn|
        conn.use ::GitHub::FaradayMiddleware::Retries,
          max:                 2,    # retries (in addition to the first request)
          interval:            0.05, # seconds
          interval_randomness: 0.5,  # percentage
          backoff_factor:      2,    # multiplier
          retry_block:         proc { GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries") },
          retry_statuses:      [429, 500, 502, 503, 504]
      end
    end

    def generate_header(req, subject)
      secret = @hmac_secrets.split(";")[0]
      req.headers["Subject"] = subject
      req.headers["Authorization"] = generate_auth_header(Time.now.to_i.to_s, secret)
    end

    def generate_auth_header(timestamp, key)
      signed_values = generate_hmac(key, timestamp)
      "HMAC-SHA256 #{timestamp}.#{Base64.strict_encode64(signed_values)}"
    end

    def generate_hmac(key, data)
      OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), Base64.decode64(key), data)
    end

    sig { params(json_result: T::Hash[String, T.untyped]).returns(NetworkConfiguration) }
    def parse_network_configuration(json_result)
      compute_services = json_result["computeServices"] || []
      enabled_service = ComputeService.try_deserialize(compute_services.find { |service| service.fetch("enabled") }&.dig("name")) || ComputeService::None

      network_resources = json_result["networkResources"]
      service = "Azure private network"
      NetworkConfiguration.new.tap do |network_configuration|
        network_configuration.name = json_result["name"]
        network_configuration.id = json_result["id"]
        network_configuration.compute_service = enabled_service
        network_configuration.service = service
        network_configuration.runner_groups = compute_services.find { |service| service["name"] == "actions" }&.dig("resources") || []
        network_configuration.compute_resources = compute_services
        network_configuration.network_setting_references = network_resources.map { |n| NetworkSettingReference.new(id: n["id"]) }
        network_configuration.created_on = json_result["createdOn"]
      end
    end

    sig { params(json_result: T::Hash[String, T.untyped]).returns(ComputeResourceConfiguration) }
    def parse_compute_resources(json_result)
      ComputeResourceConfiguration.new(
        id: json_result["id"],
        service: json_result["service"],
        network_configuration: parse_compute_resource_network_configuration(json_result["networkConfiguration"])
      )
    end

    sig { params(json_object: T::Hash[String, T.untyped]).returns(ComputeResourceNetworkConfiguration) }
    def parse_compute_resource_network_configuration(json_object)
      ComputeResourceNetworkConfiguration.new(
        id: json_object["id"],
        enabled: json_object["enabled"],
        network_resources: json_object["networkResources"]&.map { |n| parse_compute_resource_network_resource(n) } || []
      )
    end

    sig { params(json_object: T::Hash[String, T.untyped]).returns(ComputeResourceNetworkResource) }
    def parse_compute_resource_network_resource(json_object)
      ComputeResourceNetworkResource.new(
        id: json_object["id"],
        name: json_object["name"],
        state: json_object["state"],
        location: json_object["location"],
        subnet_id: json_object["subnetId"]
      )
    end

    sig { params(json_object: T::Hash[String, T.untyped]).returns(NetworkSettings) }
    def parse_network_settings(json_object)
      subnet_id_parts = json_object["subnetId"].split("/")
      NetworkSettings.new.tap do |network|
        network.id = json_object["id"]
        network.resource_id = json_object["resourceId"]
        network.display_name = json_object["name"]
        network.location = json_object["location"]
        network.resource_group = json_object["resourceGroup"]
        network.subnet_id = json_object["subnetId"]
        network.subnet = subnet_id_parts[-1]
        network.subscription = json_object["subscription"]
        network.virtual_network = subnet_id_parts[-3]
        network.state = json_object["state"]
        network.resource_name = json_object["name"]
        network.network_configuration_id = json_object["networkConfigurationId"]
      end
    end

    sig { params(response: T.untyped).returns(NetworkServiceError) }
    def get_response_error_message(response)
      if response.status == 404
        return NetworkServiceError.new("Not Found", "NotFound")
      end

      body = response.body
      return NetworkServiceError.new("unknown error", "UnknownError") if body.blank?

      json = JSON.parse(body)
      return NetworkServiceError.new("unknown error", "UnknownError") if !json["error"].present?

      error = json["error"]
      NetworkServiceError.new(error["message"], error["code"])
    rescue JSON::ParserError
      error = body.present? ? body : "unknown error"
      NetworkServiceError.new(error, "UnknownError")
    end
  end
end
