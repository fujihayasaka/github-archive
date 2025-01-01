# typed: true
# frozen_string_literal: true

module SetLoggedOutCookieConcern
  extend ActiveSupport::Concern
  extend T::Helpers

  abstract!

  requires_ancestor { ApplicationController }

  # Sets a short duration cookie used to indicate to JS that the user logged
  # out some frontend actions like clearing data should be taken as a result.
  def set_logged_out_cookie
    cookies[GitHub::Authentication::LogoutResult::SUCCESS_KEY] = {
      value: "1",
      expires: 2.minutes.from_now,
      secure: request && request.ssl?,
      domain: cookie_domain
    }
  end
end
