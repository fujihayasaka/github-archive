# frozen_string_literal: true

# Wraps an action class that resets a Repository's UpdateConfig by deactivating
# any existing rows and clearing the config_file_path
class ResetConfigFileJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  def perform(repo:)
    ProcessConfigFile::ResetConfiguration.new(repo: repo).run
  end
end
