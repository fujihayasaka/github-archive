# frozen_string_literal: true

class InstallationRepositoriesAddedProcessor < ApplicationProcessor
  group_name "installation_repositories_added"
  handle_topic(/github\.v1\.IntegrationInstallationRepositoriesAdded\Z/, InstallationRepositoriesAddedHandler)

  def initialize
    options[:session_timeout] = 15.minutes
  end
end
