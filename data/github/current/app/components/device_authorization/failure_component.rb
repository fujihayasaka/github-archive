# typed: true
# frozen_string_literal: true

module DeviceAuthorization
  class FailureComponent < ApplicationComponent
    OAUTH_APPLICATION_SUSPENDED_DESCRIPTION = \
      GitHub::HTMLSafeString.make("Check out our <a href='#{DeviceAuthorizationRequest::OAUTH_APPLICATION_SUSPENDED}'>developer docs</a> to find out more.")
    GITHUB_APP_SUSPENDED_DESCRIPTION = \
      GitHub::HTMLSafeString.make("Check out our <a href='#{DeviceAuthorizationRequest::GITHUB_APP_SUSPENDED}'>developer docs</a> to find out more.")

    def initialize(reason: nil)
      @reason = reason&.to_sym
    end

    def description
      case @reason
      when :oauth_application_suspended
        OAUTH_APPLICATION_SUSPENDED_DESCRIPTION
      when :github_app_suspended
        GITHUB_APP_SUSPENDED_DESCRIPTION
      when :spammy_application
        "The owner of this application has been marked as spammy."
      when :expired
        "Please go back to your device to request another code."
      when :not_found
        "Please make sure you entered the user code correctly."
      else
        "Please try again."
      end
    end

    def octicon_name
      case @reason
      when :expired
        "clock"
      when :not_found
        "question"
      else
        "x"
      end
    end

    def icon_color
      case @reason
      when :expired, :not_found
        :default
      else
        :danger
      end
    end

    def title
      case @reason
      when :oauth_application_suspended, :github_app_suspended
        "Application is suspended"
      when :spammy_application
        "Application might be spammy"
      when :expired
        "Expired user code"
      when :not_found
        "Uh oh, we couldn't find anything"
      else
        "Uh oh, something went wrong"
      end
    end
  end
end
