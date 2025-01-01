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

    settings_response = user.newsies_settings_response
    if settings_response.failed?
      return :unavailable
    end

    if !settings_response.settings_enabled_for?(:web)
      return :disabled
    end

    global_response = GitHub.newsies.web.exist(user, unread: true)

    if global_response.failed?
      return :unavailable
    end

    if global_response.value?
      return :global
    end

    :none
  end
end
