# typed: true
# frozen_string_literal: true

# This class is heavily tested via the middleware
# test/models/api/middleware/programmatic_access_validator_test.rb
class Api::ProgrammaticAccessValidator
  class ConfigurationError < RuntimeError
    attr_reader :reason, :token_type
    def initialize(message:, reason:, token_type: nil)
      @reason = reason
      @token_type = token_type
      super(message)
    end
  end

  class Result
    ENABLE_ACCESS_GUIDE_URL = "https://aka.ms/fine-grained-permissions-docs"
    PA_CONFIG_PATH = "github/config/access_control/programmatic_access.yaml"
    PERMISSIONS_REVIEW_TEMPLATE = "https://github.com/github/permissions/issues/new?template=01_permissions_review.md"
    PERMISSIONS_ISSUES = "https://github.com/github/permissions/issues"


    attr_reader :error, :endpoint, :token_type

    def self.success(); new(:success) end

    def self.failed(error, endpoint, token_type: nil)
      new(:failed, error: error, endpoint: endpoint, token_type: token_type)
    end

    def initialize(status, error: nil, endpoint: nil, token_type: nil)
      @status = status
      @error = error
      @endpoint = endpoint
      @token_type = token_type
    end

    def success?
      @status == :success
    end

    def failed?
      @status == :failed
    end

    def message
      output = "\n\nHello, it looks like you are modifying a REST API endpoint that is not configured to work with GitHub Apps. \n\n"

      case error
      when :missing_reason_for_disabled_token, :invalid_reason_for_disabled_token
        output += "The `#{endpoint}` endpoint is currently disabled for #{token_type} access. \n"
        output += "Please refer to the documentation for instructions on enabling this endpoint or requesting an exemption: \n"
      when :missing_endpoint_configuration
        output += "The `#{endpoint}` endpoint must have a configuration entry under #{PA_CONFIG_PATH}. \n"
        output += "For instructions on how to automatically generate the endpoint configuration, please see this guide: \n"
      when :invalid_permissions_review
        output += "The `#{endpoint}` endpoint must have a valid permission review issue. \n"
        output += "Find the approved issue for your enterprise permission at #{PERMISSIONS_ISSUES}. \n"
        output += "If your enterprise permission has not been reviwed yet, submit it for review at #{PERMISSIONS_REVIEW_TEMPLATE}. \n"
        output += "Please refer to the documentation for instructions on enabling this endpoint or enterprise permissions review: \n"
      end

      output + "#{ENABLE_ACCESS_GUIDE_URL}\n"
    end

    def exception
      return nil unless failed?
      ConfigurationError.new(message: self.message, reason: self.error, token_type: self.token_type)
    end
  end

  attr_reader :result, :endpoints, :env

  def initialize(env, endpoints)
    @env = env
    @endpoints = endpoints
  end

  def validate!
    # TODO: remove me once the endpoints are injected
    return Result.success if endpoints.empty?

    # Technically possible on requests for invalid paths (not found).
    # That concern should be handled in a different place
    return Result.success if env["github.api.route"].blank?

    # env["github.api.route"] is a string of the form:
    # "GET /repositories/:repository_id/issues"
    endpoint_key = build_endpoint_key_from(env["github.api.route"])
    endpoint_config = fetch_endpoint_configuration(endpoint_key)

    unless endpoint_config
      return Result.failed(:missing_endpoint_configuration, endpoint_key)
    end

    validate_programmatic_access_config(endpoint_key, endpoint_config.deep_symbolize_keys)
  end

  private

  def build_endpoint_key_from(route)
    # Transform escaped forward slashes back to the unescaped form
    # because the access_definitions paths are not escaped
    route.gsub("\\/", "/")
  end

  def fetch_endpoint_configuration(endpoint_key)
    endpoint = endpoints.fetch(endpoint_key, nil)
    return endpoint if endpoint.present?

    # If no endpoint was found, and this is a HEAD request, fallback
    # to the configuration for the GET method
    return nil unless endpoint_key.starts_with?("HEAD")
    get_endpoint_key = endpoint_key.gsub("HEAD", "GET")
    endpoints.fetch(get_endpoint_key, nil)
  end

  def validate_programmatic_access_config(endpoint, config)
    server_to_server_result = validate_config_for_token_type(
      endpoint, config[:server_to_server], "server_to_server",
    )
    return server_to_server_result if server_to_server_result.failed?

    user_to_server_result = validate_config_for_token_type(endpoint, config[:user_to_server], "user_to_server")
    return user_to_server_result if user_to_server_result.failed?

    validate_config_for_permissions_review(endpoint, config)
  end

  def validate_config_for_token_type(endpoint, config, token_type)
    return Result.success if config[:enabled]

    # if it's not enabled, make sure there's a valid reason
    unless config[:reason].present?
      return Result.failed(:missing_reason_for_disabled_token, endpoint, token_type: token_type)
    end

    parsed_url = URI.parse(config[:reason])
    if parsed_url.host == "github.com" && parsed_url.path =~ /api-permissions\/issues/
      return Result.success
    end

    Result.failed(:invalid_reason_for_disabled_token, endpoint, token_type: token_type)
  end

  def validate_config_for_permissions_review(endpoint, config)
    # unless any permission_sets contain a permission prefixed with "enterprise_"
    return Result.success unless config.fetch(:permission_sets, []).flat_map(&:keys).any? { |perm| perm.starts_with?("enterprise_") }

    return Result.failed(:invalid_permissions_review, endpoint) unless config[:permissions_review].present?

    parsed_url = URI.parse(config[:permissions_review])
    if parsed_url.host == "github.com" && parsed_url.path =~ /permissions\/issues/
      return Result.success
    end

    Result.failed(:invalid_permissions_review, endpoint) unless config[:permissions_review].present?
  end
end
