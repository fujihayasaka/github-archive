# typed: false
# frozen_string_literal: true

module Api::App::SCIMHelpers
  private

  # Private: Organization SCIM is disabled if
  #
  # - the organization belongs to a business and that business has a `saml_provider` configured
  # - the organization does not belong to a business and does not have SAML configured
  #
  # Business SCIM is disabled if
  #
  # - the business does not have SAML configured
  # - REVIEW - do we want to check here if Provisioning is enabled?
  #
  # Returns: boolean
  def scim_processing_error_code?(target:, disable_org_scim: false)
    return 404 if target.nil?
    return 429 if disable_org_scim

    if target.is_a?(Organization) && target.sso_enabled_on_business?
      return 403, "SCIM is not enabled for this organization: SAML SSO is configured on the enterprise account."
    end
    404 unless target.saml_sso_enabled?
  end

  # Expected response for rate limited requests is 429 in SCIM.
  # For reference see https://tools.ietf.org/html/rfc6585#section-4
  def rate_limit_status_code
    429
  end

  # Overrides handling of invalid input schemas to respond with the expected
  # SCIM error format.
  def deliver_schema_validation_error!(result)
    error_messages = "Misconfigured IdP, missing or misconfigured attributes:\n#{result.error_messages.join("\n")}"

    deliver_scim_error! 400, scim_type: "invalidSyntax", detail: error_messages, result: nil
  end

  # Private: Delivers a SCIM formatted error and halts processing.
  #
  # https://tools.ietf.org/html/rfc7644#section-3.12
  #
  # status    - The Integer status code for the error.
  # scim_type - (Optional) A String error type as defined by the spec.
  # detail    - (Optional) A human-readable message describing the error.
  # result    - (Optional) The Platform::Provisioning::Result triggering error handling (for logging).
  #
  # Returns nothing.
  def deliver_scim_error!(status, result:, scim_type: nil, detail: nil)
    scim_error = SCIM::ErrorResponse.new(status: status, scim_type: scim_type, detail: detail)

    if result&.internal_error?
      Failbot.report!(
        result.errors.get(Platform::Provisioning::Error::INTERNAL_ERROR),
        error_messages: result.error_messages
      )
    end

    halt deliver_scim(:scim_error_hash, scim_error, status: status)
  end

  # Private: Delivers a SCIM formatted response
  #
  # serialize_method  - A symbol indicating the serializing method to use.
  # obj               - The object to be serialized.
  # options           - A Hash of options that will be passed to the serializer and delivery.
  #
  # Returns the body to be rendered.
  def deliver_scim(serialize_method, obj, options = {})
    pretty = user_agent.cli? || user_agent.browser?
    extra_newline = pretty ? "\n" : ""

    serializer_options = options.except(:status)
    hash = Api::Serializer.serialize(serialize_method, obj, serializer_options)
    body = encode_json(hash, pretty: pretty) + extra_newline

    deliver_raw(body, options.reverse_merge(content_type: SCIM::CONTENT_TYPE))
  end

  # Private: Halts and delivers 404 error with human readable detail.
  #
  # id The non-existent resource id.
  #
  # Returns nothing.
  def deliver_resource_not_found!(id)
    deliver_scim_error!(404, detail: "Resource #{ id } not found.", result: nil)
  end

  # Private: Paginates the identities that were matched by the current query
  # and returns an object containing details of the pagination.
  #
  # https://tools.ietf.org/html/rfc7644#section-3.4.2.4
  #
  # identities - An ExternalIdentity scope.
  #
  # Returns a SCIM::ResultsCollection.
  def paginated_results(identities)
    total_results = identities.count
    paged = identities.offset(start_index - 1).limit(count)

    SCIM::ResultsCollection.new \
      resources: paged,
      total_results: total_results,
      start_index: start_index
  end

  # Private: The starting offset to begin pagination. SCIM uses 1-based indexes.
  #
  # Returns an Integer.
  def start_index
    [Integer(params[:startIndex]), 1].max
  rescue TypeError, ArgumentError
    1
  end

  # Private: The number of resources to return. If requested count is larger
  # than max_per_page, it is returned instead.
  #
  # Returns an Integer.
  def count
    count = [Integer(params[:count]), max_per_page].min
    count = default_per_page if count <= 0
    count
  rescue TypeError, ArgumentError
    default_per_page
  end
end
