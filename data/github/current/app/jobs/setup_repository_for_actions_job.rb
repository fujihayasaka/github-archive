# typed: true
# frozen_string_literal: true

require "github/launch_client"

class SetupRepositoryForActionsJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :actions

  def perform(repository:)
    # Actions must be enabled
    return unless GitHub.actions_enabled?

    # The app must be installed
    return unless repository.actions_app_installed?

    # This should not be done already
    return if has_workflow_runs?(repository)

    Launch::Twirp.deployer_client.setup_repository(repository:)
  end

  def has_workflow_runs?(repository)
    repository.workflow_runs.any?
  end
end
