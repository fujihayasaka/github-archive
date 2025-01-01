# typed: true
# frozen_string_literal: true

module GitHub
  module TaggingHelper
    EMPTY_HASH = {}.freeze
    EMPTY_ARRAY = [].freeze
    EMPTY_STRING = ""
    SLASH = "/"
    UNDERSCORE = "_"

    # Tag names used in Datadog metrics and traces
    RAILS_VERSION_TAG = "rails_version"
    CATEGORY_TAG = "category"
    API_TAG = "api"
    INTERNAL_API_TAG = "internal_api"
    PJAX_TAG = "pjax"
    TURBO_TYPE_TAG = "turbo_type"
    REACT_TYPE_TAG = "react_type"
    LOGGED_IN_TAG = "logged_in"
    STAFF_TAG = "staff"
    IS_ROBOT_TAG = "is_robot"
    DATABASE_CLUSTER_TAG = "database_cluster"
    DATABASE_CONNECTION_ROLE_TAG = "database_connection_role"
    CONTROLLER_TAG = "controller"
    ACTION_TAG = "action"
    STATUS_TAG = "status"
    STATUS_RANGE_TAG = "status_range"
    METHOD_TAG = "method"
    COMPONENT_TAG = "component"
    GRAPHQL_API_TAG = "graphql_api"
    GRAPHQL_OPERATION_TYPE = "operation_type"
    CATALOG_SERVICE_TAG = "catalog_service"
    RESPONSE_LT6000_TAG = "response_lt6000"
    RESPONSE_LT3000_TAG = "response_lt3000"
    EMPTY_ISSUE_TAG = "empty_issue"
    PROFILE_TYPE = "profile_type"
    COMMAND_PALETTE_PROVIDER_NAME_TAG = "command_palette_provider_name"
    EXCEPTION_TAG = "exception"
    POD_NAME_TAG = "pod_name"
    ROUTE_TAG = "route"
    AUTH_TAG = "auth"
    VERSION_TAG = "version"
    REQUESTED_API_VERSION_TAG = "requested_api_version"
    SELECTED_API_VERSION_TAG = "selected_api_version"
    SELECTED_API_VERSION_REASON_TAG = "selected_api_version_reason"
    CODESPACES_AUTOMATED_TESTING_TAG = "codespaces_automated_testing"
    SUCCESS_TAG = "success"
    NAME_TAG = "name"
    AVAILABILITY_TAG = "availability"
    CLUSTER_TAG = "cluster"
    MAJOR_BY_TAG = "major_by"
    STATS_MODE_TAG = "stats_mode"
    HAS_HANDLED_EXCEPTIONS_TAG = "has_handled_exceptions"
    UNHANDLED_EXCEPTION_CLASS_TAG = "unhandled_exception_class"
    UNHANDLED_EXCEPTION_DATABASE_CLUSTER_TAG = "unhandled_exception_database_cluster"
    UNHANDLED_EXCEPTION_DATABASE_CONNECTION_ROLE_TAG = "unhandled_exception_database_connection_role"
    UNHANDLED_EXCEPTION_DATABASE_CLUSTER_STATUS_TAG = "unhandled_exception_database_cluster_status"
    EXHAUSTED_TIME_BUDGET_TAG = "exhausted_time_budget"
    RPC_STORE_TAG = "rpc_store"
    REPO_ADVISORY_SOURCE_TYPE_TAG = "github/repo_advisories/source"
    SEARCH_QUERY_CLASS_TAG = "search_query_class"

    # Possible status ranges
    STATUS_RANGE_1XX = "1xx"
    STATUS_RANGE_2XX = "2xx"
    STATUS_RANGE_3XX = "3xx"
    STATUS_RANGE_4XX = "4xx"
    STATUS_RANGE_5XX = "5xx"

    # ENV keys for accessing specific values
    REPO_ADVISORY_SOURCE_TYPE_KEY = "repo_advisory_source_type"
    COMMAND_PALETTE_PROVIDER_NAME_KEY = "command_palette_provider_name"
    ALLOY_CALLS_KEY = "alloy_calls"
    RACK_REQUEST_PARAMETERS_KEY = "rack.request.query_hash"
    RAILS_DEFAULT = "rails"
    RAILS_PARAMETERS_KEY = "action_dispatch.request.path_parameters"
    RAILS_REQUEST_PARAMETERS_KEY = "action_dispatch.request.parameters"
    API_CONTROLLER_KEY = "process.api.controller"
    INTERNAL_API_PREFIX = "Api::Internal"
    TWIRP_METHOD_ENV_KEY = "twirp.method"
    SINATRA_ROUTE_ENV_KEY = "sinatra.route"
    GITHUB_API_ROUTE_ENV_KEY = "github.api.route"
    PROCESS_REQUEST_CATEGORY = "process.request_category"
    PROCESS_REQUEST_CATEGORY_DATADOG = "process.request_category_datadog"
    CODESPACES_AUTOMATED_TESTING = "codespaces_automated_testing"
    DATADOG_BROWSER_CATEGORY = "browser"
    STATSD_SAMPLE_RATE = "process.metrics.sample_rate"
    PROCESS_SERVICE_KEY = "process.catalog_service"
    PROCESS_REQUEST_PJAX = "process.request_pjax"
    PROCESS_REQUEST_TURBO = "process.request_turbo"
    PROCESS_REQUEST_REACT_TYPE = "process.request_react_type"
    PROCESS_REQUEST_LOGGED_IN = "process.request_logged_in"
    PROCESS_REQUEST_STAFF_USER = "process.request_staff_user"
    PROCESS_REQUEST_START = "process.request_start"
    CATEGORY_DEFAULT = "other"
    PJAX_DEFAULT = LOGGED_IN_DEFAULT = "false"
    DATADOG_ROBOT_CATEGORY = "robot"
    ALLOY_WAIT_TIME = "alloy_wait_time"
    REQ_WAIT_TIME = "request_wait_time"
    GLB_WAIT_TIME = "glb_wait_time"
    REQ_CPU_TIMES = "request_cpu_times"
    UNKNOWN = "unknown"
    COUNTRY = "country"
    REQUEST_IP = "request_ip"
    RESPONSE_RANGE_TAG = "response_range"
    REQUEST_METHOD = "REQUEST_METHOD"
    SEARCH_QUERY_CLASS = "search_query_class"

    TRACKED_LATENCY_SLOS = "latency_slos"
    TRACKED_AVAILABILITY_SLOS = "availability_slos"

    # this is based on the allowlist definedin GLB
    # see: https://github.com/github/glb/blob/7803c337da105ce0785ed637685c26a47f3d0fd3/services/common/data/common.yml#L7
    KNOWN_HTTP_METHODS = %w(
      options
      propfind
      report
      mkactivity
      proppatch
      checkout
      mkcol
      move
      copy
      lock
      unlock
      merge
      get
      post
      head
      put
      delete
      connect
      trace
      patch).to_set.freeze

    def self.rails_version
      return @rails_version if defined? @rails_version
      @rails_version = GitHub.rails_version_key || RAILS_DEFAULT
    end

    def self.category(env)
      env[PROCESS_REQUEST_CATEGORY_DATADOG] || CATEGORY_DEFAULT
    end

    def self.repo_advisory_source_type(env)
      env[REPO_ADVISORY_SOURCE_TYPE_KEY]
    end

    def self.pjax(env)
      env[PROCESS_REQUEST_PJAX] || UNKNOWN
    end

    def self.turbo(env)
      env[PROCESS_REQUEST_TURBO] || UNKNOWN
    end

    def self.react_type(env)
      env[PROCESS_REQUEST_REACT_TYPE] || UNKNOWN
    end

    def self.logged_in(env)
      env[PROCESS_REQUEST_LOGGED_IN] || UNKNOWN
    end

    def self.staff_user(env)
      env[PROCESS_REQUEST_STAFF_USER] || UNKNOWN
    end

    def self.request_start(env)
      env[PROCESS_REQUEST_START]
    end

    def self.catalog_service(env)
      # keep this in sync with GitHub::ServiceMapping#push_service_mapping_context to ensure
      # unknown services are always consistently labelled.
      env[GitHub::TaggingHelper::PROCESS_SERVICE_KEY] || GitHub::Serviceowners::UNKNOWN_SERVICE
    end

    def self.internal_api?(env)
      !!(env && env[API_CONTROLLER_KEY]&.start_with?(INTERNAL_API_PREFIX))
    end

    # This is named "request_method" because
    # "method" is a reserved method name on Object.
    def self.request_method(env)
      method = env[REQUEST_METHOD]&.downcase
      KNOWN_HTTP_METHODS.include?(method) ? method : UNKNOWN
    end

    def self.calculate_referrer(env, action_suffix: "")
      referrer = env[GitHub::Middleware::Constants::HTTP_REFERER] || env["Referer"]
      return ["referrer_controller:unknown", "referrer_action:unknown"] unless referrer

      begin
        router_response = Rails.application.routes.recognize_path(referrer)
        router_response[:controller] = GitHub::TaggingHelper.formatted_controller(router_response[:controller])
      rescue ActionController::RoutingError
        return ["referrer_controller:unknown", "referrer_action:unknown"]
      end

      router_response[:controller] = "pull_requests" if router_response.fetch(:pulls_only, nil) == true

      [
        "referrer_controller:#{router_response[:controller].presence || "unknown"}",
        "referrer_action:#{router_response[:action].presence || "unknown"}#{action_suffix}"
      ]
    end

    def self.controller(env)
      controller = (path_parameters(env) || EMPTY_HASH)[:controller]
      return formatted_controller(controller) if controller

      controller = (api_parameters(env) || EMPTY_HASH)[:app]
      return formatted_controller(controller) if controller
    end

    def self.formatted_controller(controller_name)
      formatted = controller_name.to_s.underscore
      # formatted.tr! is tempting here but the underscore method above (as of
      # Rails 6.1.1) returns the original string (same object) if unmodified.
      # So using tr! may suprise the caller by modifying its passed argument.
      formatted = formatted.tr(SLASH, UNDERSCORE)
      formatted.delete_suffix!("_controller")
      formatted
    end

    def self.hook_event_type_tag_value(event_type)
      "hook/#{event_type}"
    end

    def self.hook_event_tag_value(event_type, action = nil)
      event_type = hook_event_type_tag_value(event_type)
      return event_type unless action
      "#{event_type}_#{action}"
    end

    def self.create_hook_event_tags(event_type, action = nil)
      [
        "event:#{hook_event_tag_value(event_type, action)}",
        "event_type:#{hook_event_type_tag_value(event_type)}",
      ]
    end

    def self.action(env)
      action = (path_parameters(env) || EMPTY_HASH)[:action]
      return action if action

      route = (api_parameters(env) || EMPTY_HASH)[:route]
      return nil unless route

      api_action(route)
    end

    def self.api_action(route)
      return nil unless route
      # API actions come in the form GET /emojis
      _req_method, path = route.split(" ", 2)

      return path if path

      # When the action comes from RepoPermissions, it comes preformatted without
      # the `GET /` part of the path, so we can just return it
      route
    end

    def self.path_parameters(env)
      env[RAILS_PARAMETERS_KEY]
    end

    def self.rack_parameters(env)
      env[RACK_REQUEST_PARAMETERS_KEY]
    end

    def self.request_parameters(env)
      env[RAILS_REQUEST_PARAMETERS_KEY]
    end

    def self.api_parameters(env)
      return nil unless app = api_controller(env)
      return nil unless route = api_route(env)
      { app: app, route: route }
    end

    def self.api_controller(env)
      env[API_CONTROLLER_KEY]
    end

    def self.api_route(env)
      env[TWIRP_METHOD_ENV_KEY] || env[SINATRA_ROUTE_ENV_KEY] || env[GITHUB_API_ROUTE_ENV_KEY]
    end

    def self.alloy_calls(env)
      env[ALLOY_CALLS_KEY]
    end

    def self.codespaces_automated_testing?(env)
      # "vscs_target" is the Visual Studio Codepaces service environment (production, dev, pre-production, etc).
      vscs_target =
        (rack_parameters(env) || EMPTY_HASH).dig("vscs_target") ||
        (request_parameters(env) || EMPTY_HASH).dig(:codespace, :vscs_target)
      non_production = vscs_target && vscs_target != "production"
      is_test_user = !!env[CODESPACES_AUTOMATED_TESTING]
      non_production || is_test_user
    end

    def self.graphql_api_request?(controller)
      controller == "api_graph_ql"
    end

    def self.graphql_operation_type(env)
      env[GRAPHQL_OPERATION_TYPE]
    end

    def self.profile_type(env)
      env[PROFILE_TYPE]
    end

    def self.command_palette_provider_name(env)
      env[COMMAND_PALETTE_PROVIDER_NAME_KEY]
    end

    def self.tracked_latency_slos(env)
      env[TRACKED_LATENCY_SLOS] || EMPTY_HASH
    end

    def self.tracked_availability_slos(env)
      env[TRACKED_AVAILABILITY_SLOS] || EMPTY_ARRAY
    end

    def self.add_status_range_tag(tags, status_code)
      add_tag tags, STATUS_RANGE_TAG, status_range(status_code)
    end

    def self.add_tag(tags, tag, tag_value)
      tags << "#{tag}:#{tag_value}"
    end

    def self.add_tag_unless_nil(tags, tag_name, tag_value)
      tags << "#{tag_name}:#{tag_value}" unless tag_value.nil?
    end

    def self.status_range(status)
      case status
      when 100..199
        STATUS_RANGE_1XX
      when 200..299
        STATUS_RANGE_2XX
      when 300..399
        STATUS_RANGE_3XX
      when 400..499
        STATUS_RANGE_4XX
      when 500..599
        STATUS_RANGE_5XX
      else
        status
      end
    end

    # Sets `action_dispatch.request.path_parameters[:controller]` tag to given string.
    # For use when you need to override actual controller that's passed to Splunk, Datadog, etc.
    #
    # Use with caution. Can result in unexpected exceptions downstream.
    # See https://github.com/github/issues/issues/5215.
    #
    # env - Rack environment
    # controller - String controller name
    #
    # Returns Hash of path parameters (ex. {:controller=>"issues", :action=>"dashboard"})
    def self.override_controller_tag(env:, controller:)
      controller_tag_key = GitHub::TaggingHelper::CONTROLLER_TAG.to_sym
      path_parameters(env)[controller_tag_key] = controller
      path_parameters(env)
    end

    # Sets `action_dispatch.request.path_parameters[:action]` tag to given string.
    # For use when you need to override actual action that's passed to Splunk, Datadog, etc.
    #
    # Use with caution. Can result in unexpected exceptions downstream.
    # See https://github.com/github/issues/issues/5215.
    #
    # env - Rack environment
    # action - String action name
    #
    # Returns Hash of path parameters (ex. {:controller=>"issues", :action=>"dashboard"})
    def self.override_action_tag(env:, action:)
      action_tag_key = GitHub::TaggingHelper::ACTION_TAG.to_sym
      path_parameters(env)[action_tag_key] = action
      path_parameters(env)
    end
  end
end
