# typed: true
# frozen_string_literal: true

module Api::App::ContentAuthorizationDependency
  extend T::Helpers
  requires_ancestor { Api::App::ErrorDependency }

  def deliver_content_authorization_denied!(authorization)
    instrument_content_authorization_failure(error: authorization.api_error)
    deliver_error! authorization.http_error_code, authorization.api_error_payload
  end
end
