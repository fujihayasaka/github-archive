# typed: true
# frozen_string_literal: true

module ApplicationController::NotificationsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    helper_method :notification_referrer
    helper_method :notifications_referrer_params
    helper_method :show_notification_shelf?
  end

  # Returns the notification referrer parameters, and permits them
  # so they can be used in redirects if required
  def notifications_referrer_params
    params.slice(*NotificationsV2Controller::REFERRER_PARAMS).permit!
  end

  def notification_referrer
    return @notification_referrer if defined?(@notification_referrer)

    @notification_referrer = if params[:notification_referrer_id]
      access = notification_referrer_access
      return access if access == :conditional_access_error

      begin
        # This uses `PlatformHelper.typed_object_from_id` in order to perform authorization checks for the viewer
        # prior to returning the object.
        #
        # The resulting value is of type Platform::Models::NotificationThread.
        notification_thread_model = typed_object_from_id(
          [Platform::Objects::NotificationThread],
          params[:notification_referrer_id],
          cap_filter: cap_filter,
        )
        return :not_found_error unless notification_thread_model

        subscription_status = Platform::Security::RepositoryAccess.with_viewer(current_user) do
          notification_thread_model.subscription_status
        end

        {
          id: notification_thread_model.global_relay_id,
          is_archived: notification_thread_model.archived?,
          is_starred: notification_thread_model.starred?,
          is_unread: notification_thread_model.unread?,
          subscription_status: subscription_status
        }
      rescue Platform::Errors::NotFound
        :not_found_error
      rescue PlatformHelper::ConditionalAccessError
        # This exception means that the user session is currently failing SAML/IP/etc checks
        :conditional_access_error
      rescue StandardError => e # rubocop:todo Lint/RescueException
        # Rescuing any StandardError here as we really don't errors in shelf rendering
        # to cause 500s for the page we are trying to navigate.
        if Rails.env.production?
          NotificationsFailbot.report(e)
        else
          raise e
        end
      end
    end
  end

  def notification_referrer_access
    # Don't return a notification if the current controller is going to
    # render the SSO login prompt
    if GitHub.external_identity_session_enforcement_enabled? &&
      require_active_external_identity_session? &&
      !external_identity_session_fresh?

      return :conditional_access_error
    end

    :allowed
  end

  def show_notification_shelf?
    params[:notification_referrer_id].present? && notification_referrer_access != :conditional_access_error
  end
end
