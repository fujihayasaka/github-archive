# typed: false
# frozen_string_literal: true

# Many browser security issues stem from the browser misinterpreting the
# content type of a response. For example, the server might return a JSON
# payload, but the browser might see the PDF magic bytes in the JSON and assume
# that it is actually a PDF file.
#
# The `block_non_xhr_json_responses` after_action ensures that JSON responses
# are in response to XHR requests. This helps to prevent browsers from
# interpreting JSON responses as other content-types.
module ApplicationController::JsonXhrRequirementDependency
  # Blocks JSON responses to non-XHR requests.
  #
  # Returns nothing.
  def block_non_xhr_json_responses
    head(400) unless allowed_json_response?
  end

  # Is this a response that should be blocked?
  #
  # Returns boolean.
  def allowed_json_response?
    # This protection is disabled on Enterprise.
    return true if !GitHub.json_xhr_requirement_enabled?

    # All non-JSON responses are allowed.
    return true if !response.media_type.to_s.start_with?("application/json")

    # Non-200 JSON responses are allowed because they contain error messages.
    return true if !response.ok?

    # XHR requests are allowed to receive JSON responses. Some XHR requests set
    # the `X-Requested-With: XMLHttpRequest` header.
    return true if request.xhr?

    # XHR requests are allowed to receive JSON responses. Some XHR requests set
    # the `Accept: application/json` header.
    return true if request.format.present? && request.format.json?

    # Deny browser requests for a JSON response.
    false
  end
end
