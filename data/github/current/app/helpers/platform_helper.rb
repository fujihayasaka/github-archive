# typed: false
# frozen_string_literal: true

require "graphql/client"

module PlatformHelper
  extend T::Helpers

  module ClassMethods
    sig { params(str: String).returns(T.untyped) }
    def parse_query(str)
      location = caller_locations(1, 1).first
      PlatformHelper::PlatformClient.parse(str, location.path, location.lineno)
    end
  end

  mixes_in_class_methods(ClassMethods)

  class Error < StandardError; end
  class ExecutionError < Error; end
  class MutationInputError < Error; end
  class InvalidCursorError < Error; end
  class ConditionalAccessError < Error; end
  class SamlError < ConditionalAccessError; end
  class IpAllowListError < ConditionalAccessError; end
  class EmuOwnershipError < ConditionalAccessError; end
  class EmuVisibilityError < ConditionalAccessError; end
  class EnterpriseAccessVerificationError < ConditionalAccessError; end
  class ExternalConditionalAccessPolicyError < ConditionalAccessError; end

  class PlatformExecute
    def self.execute(document:, operation_name: nil, variables: {}, context: {}, request_env: nil)
      # Only validate internal queries if we are also analyzing internal queries - default false in all environments
      validate = GitHub.analyze_internal_graphql?
      Platform.execute(
        document,
        target: :internal,
        context: context,
        variables: variables,
        raise_exceptions: true,
        validate: validate,
        request_env: request_env,
      ).to_h
    end
  end

  MAX_PLATFORM_EXECUTE_CALLS = 6
  STAFF_BAR_CALLS = 1

  def platform_execute(operation, variables: {}, context: {})
    if Rails.env.development? || Rails.env.test?
      @platform_execute_calls ||= 0
      @platform_execute_calls += 1

      max_calls = MAX_PLATFORM_EXECUTE_CALLS
      max_calls += STAFF_BAR_CALLS if respond_to?(:staff_bar_enabled?) && staff_bar_enabled?

      if @platform_execute_calls > max_calls
        fail "Too many platform_execute calls"
      end
    end

    merged_context = platform_context.merge(context)

    response = PlatformHelper::PlatformClient.query(operation, context: merged_context, variables: variables)

    raise_on_conditional_access_errors!(response)
    response.errors[:data].each do |message|
      case message
      when /Variable \$input/
        raise MutationInputError, message
      when /valid cursor/
        # A malformed cursor was entered to the UI (maybe user-generated).
        # It was posted to datadog by Errors::Cursor#initialize.
        Failbot.push(app: "github-invalid-cursor")
        raise InvalidCursorError, message
      else
        raise ExecutionError, message
      end
    end

    response.data
  end

  def raise_on_conditional_access_errors!(response)
    response.errors.all[:data].each do |message|
      case message
      when /IP not allowed/
        raise IpAllowListError, message
      when /saml error/
        raise SamlError, message
      when /Unauthorized operation for Enterprise Managed User/
        raise EmuOwnershipError, message
      when /Unauthorized operation for a user accessing Enterprise Managed User/
        raise EmuVisibilityError, message
      when /Your network administrator has blocked access to GitHub except for the/, /Only one enterprise can be used with the 'sec-GitHub-allowed-enterprise header'/, /The enterprise named in the 'sec-GitHub-allowed-enterprise' header cannot be found/, /Too many enterprises are specified/
        raise EnterpriseAccessVerificationError, message
      when  /IdP based IP allowlist blocked/, /IdP error message/
        raise ExternalConditionalAccessPolicyError, message
      end
    end
  end

  def platform_context
    GitHub.tracer.in_span("PlatformHelper#platform_context",
                          attributes: {
                            "code.namespace" => controller_name,
                            "code.function" => action_name,
                          }.reject { |_, v| v.nil? }, kind: :internal) do |_span|
      {
        origin: Platform::ORIGIN_INTERNAL,
        viewer: current_user,
        log_data: log_data,
        session: session,
        user_session: user_session,
        rails_request: request,
        force_readonly_primary: !(request.get? || request.head?),
        controller: controller_name,
        action: action_name,
        unauthorized_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.resources_for_cap_filter),
        cap_filter: cap_filter,
        performance_trace: stats_ui_enabled? && params["graphql_query_trace"],
        performance_trace_field_profile_path: stats_ui_enabled? ? params["graphql_query_trace_profile_path"] : nil,
        performance_trace_field_profile_type: if stats_ui_enabled?
                                                params["graphql_query_trace_profile_kind"] == "lines" ? :lines : :allocations
                                              else
                                                nil
                                              end,
        request_access_security_header: request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
    }
    end
  end

  def typed_object_from_id(possible_type_or_types, id, **permission_options)
    Platform::Security::RepositoryAccess.with_viewer(current_user) do
      permission    = Platform::Authorization::Permission.new(viewer: current_user, origin: Platform::ORIGIN_INTERNAL, **permission_options)
      Platform::Helpers::NodeIdentification.typed_object_from_id(possible_type_or_types, id, permission: permission)
    end
  end

  # Our template precompiler can't handle recursive partials, so work around that
  def render_graphql_node(node)
    if node.is_a?(Platform::PerformancePaneTracer::DisplayPhase)
      render partial: "stafftools/staffbar/graphql_stats_phase", locals: { node: node }
    else
      render partial: "stafftools/staffbar/graphql_stats_step", locals: { node: node }
    end
  end

  def render_graphql_ms(milliseconds)
    "%.1fms" % milliseconds
  end

  def encode_parameters(param)
    case param
    when Array
      param.map { |element| encode_parameters(element) }
    when Hash
      Hash[param.map { |key, value| [key, encode_parameters(value)] }]
    when String
      if (param.encoding == ::Encoding::US_ASCII || param.encoding == ::Encoding::UTF_8) && param.valid_encoding?
        param
      else
        param.dup.force_encoding(::Encoding::UTF_8).scrub!
      end
    end
  end
end
