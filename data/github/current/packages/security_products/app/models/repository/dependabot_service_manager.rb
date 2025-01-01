# typed: true
# frozen_string_literal: true

# This class provides an interface to check and modify non-user Dependabot configuration.
class Repository::DependabotServiceManager
  PAUSED_KEY  = "dependabot.paused"

  attr_reader :repository

  def initialize(repository)
    @repository = repository
  end

  # has Dependabot been paused due to inactivity?
  def paused?
    repository.config.enabled?(PAUSED_KEY)
  end

  # set the paused flag
  def pause
    return true if paused?

    repository.config.enable(PAUSED_KEY, actor)
    GlobalInstrumenter.instrument(PAUSED_KEY, instrumentation_payload)
    true
  end

  # clear the paused flag
  def unpause
    return true unless paused?

    repository.config.delete(PAUSED_KEY, actor)
    GlobalInstrumenter.instrument("dependabot.unpaused", instrumentation_payload)
    true
  end

  private

  def actor
    GitHub.dependabot_github_app_bot
  end

  def instrumentation_payload
    {
      repository: repository,
      owner: repository.owner
    }
  end
end
