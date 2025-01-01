# typed: true
# frozen_string_literal: true

class Api::Git < Api::App

  # Private endpoint used by GitHub Desktop to determine (via the
  # X-Poll-Interval header) how often this repository should be `git fetch`ed.
  get "/repositories/:repository_id/git", operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/repos"
    control_access :git_poll,
      resource: find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_poll_interval_header!

    deliver_empty status: 204
  end

  private

  def poll_interval
    if desktop_high_fetch_frequency_enabled?
      GitHub.desktop_fetch_interval.minutes
    else
      1.hour
    end
  end

  def desktop_high_fetch_frequency_enabled?
    return false unless user_agent.github_desktop?

    if user_agent.github_desktop?
      true
    else
      case user_agent.github_app_version.major
      when 0..207
        false
      when 208
        user_agent.github_app_version.minor >= 1
      else
        true
      end
    end
  end
end
