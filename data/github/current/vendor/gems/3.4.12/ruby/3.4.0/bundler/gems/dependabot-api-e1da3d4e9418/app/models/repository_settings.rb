# frozen_string_literal: true

class RepositorySettings
  class RepoNotFound < StandardError; end

  def initialize(repo)
    @repo = repo
  end

  def grouped_security_updates_enabled?
    settings.security_updates_grouping_enabled
  end

  private

  attr_reader :repo

  def settings
    @settings ||= client.get_repository_settings(repo)
  rescue GitHub::Twirp::DependabotRepositorySettings::NotFound
    raise RepoNotFound
  end

  def client
    Dependabot::Application.dependabot_repository_settings_client
  end
end
