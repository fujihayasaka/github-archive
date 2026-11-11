# typed: false
# frozen_string_literal: true

module ApplicationController::EmailTrackingDependency
  # This method facilitates email link tracking. A URL param of `email_source` is required in order
  # to track new emails
  def track_emails
    if FeatureFlag.vexi.enabled?(:change_email_link_tracking, current_user, default: false)
      email_source = params["email_source"]
      track_notification_email_clicks if email_source.present? && params["email_token"].present?

      safe_redirect_to(email_tracking_redirect_url) if email_source.present?
    else
      email_source = params["email_source"]

      return track_notification_email_clicks if email_source == "notifications"

      if email_source.present?
        GlobalInstrumenter.instrument("user.email_link_click",
          email_source: email_source,
          user: current_user,
          auto_subscribed: params["auto_subscribed"] == "true")

        safe_redirect_to(email_tracking_redirect_url)
      end
    end
  end

  private

  def track_notification_email_clicks
    if FeatureFlag.vexi.enabled?(:change_email_link_tracking, current_user, default: false)
      if FeatureFlag.vexi.enabled?(:notifyd_tracking_token_by_service, current_user, default: false)
        response = ::Notifyd::EmailLinkTracking.new(params["email_token"]).track

        unless response
          if FeatureFlag.vexi.enabled?(:newsies_email_tracking_change_params, current_user, default: false)
            GitHub.newsies.track_email_link_click(current_user, params["email_token"], { reason: params[:reason], event: params[:event] })
          else
            GitHub.newsies.track_email_link_click(current_user, params["email_token"])
          end
        end
      else
        GitHub.newsies.track_email_link_click(current_user, params["email_token"])
      end
    else
      if FeatureFlag.vexi.enabled?(:notifyd_tracking_token_by_service, current_user, default: false)
        response = ::Notifyd::EmailLinkTracking.new(params["email_token"]).track if params["email_token"].present?

        unless response
          GitHub.newsies.track_email_link_click(current_user, params["email_token"]) if params["email_token"].present?
        end
      else
        GitHub.newsies.track_email_link_click(current_user, params["email_token"]) if params["email_token"].present?
      end
      safe_redirect_to(email_tracking_redirect_url)
    end
  end

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
