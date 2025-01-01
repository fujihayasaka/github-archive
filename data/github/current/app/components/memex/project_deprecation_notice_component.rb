# typed: true
# frozen_string_literal: true

class Memex::ProjectDeprecationNoticeComponent < ApplicationComponent
  attr_reader :project, :data_url

  # project - the project (classic)
  # data_url - the url (path) to use to fetch the partial's html. Used for enabling live-updates via Alive. See: https://github.com/github/alive/blob/main/docs/how-to-use-alive.md#live-updates
  def initialize(project:, data_url:)
    @project = project
    @data_url = data_url
  end

  def changelog_url
    "https://gh.io/projects-classic-sunset-notice"
  end

  def migration
    project.project_migration
  end

  memoize def channel
    live_update_view_channel(GitHub::WebSocket::Channels.project_metadata(project))
  end

  def show_migration_button?
    !migration.present?
  end

  def memex_url
    migration&.memex_project&.url if migration&.completed?
  end

  def notice
    GitHub.enterprise? ? "Projects (classic) will be sunset in GitHub Enterprise Server 3.16" : "Projects (classic) will be sunset on August 23, 2024"
  end

  def reopen_message
    "This project can no longer be reopened." if project.closed?
  end

  def status_text
    return "We encourage you to migrate this project to the new Projects experience." unless migration.present?
    return "This project has been migrated from Projects (classic) to Projects by #{migration.requester.display_login}. #{reopen_message}" if migration&.completed?
    return "There was a problem migrating this project." if migration&.error?

    # migration is in progress
    "This project is being migrated from Projects (classic) to Projects. Please wait for it to complete."
  end
end
