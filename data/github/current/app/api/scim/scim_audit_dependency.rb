# typed: true
# frozen_string_literal: true

module Api::SCIM::SCIMAuditDependency
  extend T::Helpers
  requires_ancestor { Api::SCIM::BaseSCIM }

  GET_REQUEST_METHOD = "GET".freeze
  CLIENT_ERROR_HTTP_STATUS = 400.freeze
  SUCCESS_HTTP_STATUS = 200.freeze
  SCIM_AUDIT_LOG_FAILURE_SUFFIX = "scim_api_failure".freeze
  SCIM_AUDIT_LOG_SUCCESS_SUFFIX = "scim_api_success".freeze

  # make sure to downcase the attribute before adding to this list
  DEFAULT_SCIM_ATTRIBUTES = %w[schemas username name emails displayname externalid active roles groups]

  def instrument_scim_api_request
    # We don't want to log SCIM API requests for successful GET requests due to the high volume of requests
    return if request.request_method == GET_REQUEST_METHOD && response.status < CLIENT_ERROR_HTTP_STATUS

    audit_log_prefix = scim_audit_log_prefix
    audit_log_suffix = scim_audit_log_suffix
    return unless audit_log_suffix

    request.body&.rewind

    event = build_event

    if route_pattern&.include?(":external_identity_guid")
      event[scim_audit_log_external_identity_guid_field] = params[:external_identity_guid]
    end

    body = response.body&.first
    if audit_log_suffix == SCIM_AUDIT_LOG_FAILURE_SUFFIX && !body.blank?
      event[:message] = body
    end

    GitHub.instrument "#{audit_log_prefix}.#{audit_log_suffix}", event
  end

  private

  def build_event
    sanitized_api_request_body = sanitize_api_request_body(request.body&.read)
    {
      query_string: request.query_string,
      api_request_body: sanitized_api_request_body,
      request_method: request.request_method,
      route: route_pattern,
      status_code: response.status,
      url_path: request.path,
    }
  end

  def sanitize_api_request_body(api_request_body)
    # no sensitive fields to sanitize for group requests
    return api_request_body if api_namespace == :EnterpriseGroupsScim
    return api_request_body unless api_request_body
    return api_request_body unless request.request_method

    begin
      # Parse the request body into a hash
      parsed_body = JSON.parse(api_request_body)
      sanitize_sensitive_fields(parsed_body, request.request_method.downcase)
      # Convert the sanitized hash back to a JSON string
      parsed_body.to_json
    rescue JSON::ParserError
      # If parsing fails, return the original body
      api_request_body
    end
  end

  def sanitize_sensitive_fields(parsed_body, request_method)
    case request_method
    when "post", "put"
      parsed_body.select! { |key, _| DEFAULT_SCIM_ATTRIBUTES.include?(key.downcase) }
    when "patch"
      sanitize_operations(parsed_body["Operations"])
    end
  end

  def sanitize_operations(operations)
    return unless operations.is_a?(Array) && operations.any?

    operations.select! do |operation|
      if operation.key?("path")
        # Keep operation if path is in DEFAULT_SCIM_ATTRIBUTES
        DEFAULT_SCIM_ATTRIBUTES.include?(operation["path"].downcase)
      elsif operation.key?("value") && operation["value"].is_a?(Hash)
        # Filter the keys in the value hash
        operation["value"].select! { |key, _| DEFAULT_SCIM_ATTRIBUTES.include?(key.downcase) }
        true # keep operations since we have already filtered the attributes
      else
        true # default to keeping the operation if it does not satisfy the above conditions
      end
    end
  end

  def api_namespace
    @api_namespace if defined?(@api_namespace)
    @api_namespace = self.class.to_s.delete_prefix("Api::").gsub("::", "").to_sym
  end

  def scim_audit_log_prefix
    case api_namespace
    when :EnterpriseUsersScim
      "external_identity"
    else
      "external_group"
    end
  end

  def scim_audit_log_external_identity_guid_field
    case api_namespace
    when :EnterpriseUsersScim
      :scim_user_id
    else
      :scim_group_id
    end
  end

  def scim_audit_log_suffix
    if response.status >= CLIENT_ERROR_HTTP_STATUS
      SCIM_AUDIT_LOG_FAILURE_SUFFIX
    elsif response.status >= SUCCESS_HTTP_STATUS
      SCIM_AUDIT_LOG_SUCCESS_SUFFIX
    else
      nil
    end
  end
end
