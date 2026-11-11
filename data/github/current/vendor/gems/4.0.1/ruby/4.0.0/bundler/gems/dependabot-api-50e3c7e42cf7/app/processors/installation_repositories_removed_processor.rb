# frozen_string_literal: true

class InstallationRepositoriesRemovedProcessor < ApplicationProcessor
  group_name "installation_repositories_removed"
  handle_topic(/github\.v1\.IntegrationInstallationRepositoriesRemoved\Z/, InstallationRepositoriesRemovedHandler)

  def initialize
    options[:session_timeout] = 15.minutes
  end
end
