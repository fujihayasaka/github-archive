# typed: true
# frozen_string_literal: true

class User::IndicatorChecker
  # Public: Gets and fills the cache for the user's mode, if it's an available mode.
  #
  # user       - A User.
  #
  # Returns a Symbol mode.
  def mode(user)
    @mode ||= check_mode(user)
  end

  private

  def check_mode(user)
    return :none if user.nil?
    global_response = GitHub.newsies.web.exist(user, unread: true)
    return :unavailable if global_response.failed?
    return :global if global_response.value?
    return :disabled unless Notifications::Settings.web?(user)
    :none
  end
end
