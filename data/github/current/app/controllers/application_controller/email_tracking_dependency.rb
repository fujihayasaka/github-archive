# typed: false
# frozen_string_literal: true

module ApplicationController::EmailTrackingDependency
  # This method facilitates email link tracking. A URL param of `email_source` is required in order
  # to track new emails
  def track_emails
    email_source = params["email_source"]

    # Notification emails links don't need to be tracked.
    return safe_redirect_to(email_tracking_redirect_url) if email_source == "notifications"

    if email_source.present?
      GlobalInstrumenter.instrument("user.email_link_click",
        email_source: email_source,
        user: current_user,
        auto_subscribed: params["auto_subscribed"] == "true")

      safe_redirect_to(email_tracking_redirect_url)
    end
  end

  private

  def email_tracking_redirect_url
    uri_string =
      if request_coming_from_voltron?
        canonical_request.url
      else
        env["REQUEST_URI"]
      end
    uri = Addressable::URI.parse(uri_string)
    filtered_query = uri.query_values ? uri.query_values.except("auto_subscribed", "email_source", "email_token") : {}
    uri.query_values = filtered_query.empty? ? nil : filtered_query
    uri.to_s
  end

end
