# typed: true
# frozen_string_literal: true

module GitHubMobileAuthHelper
  extend T::Helpers

  # Is github mobile 2fa available as an auth factor for the environment, session, and current user?
  #
  # Returns boolean.
  def user_and_session_can_use_gh_mobile_auth?(user)
    return false unless user
    return false if T.unsafe(self).session[:is_gh_mobile_app]
    user.gh_mobile_auth_available?
  end

end
