# frozen_string_literal: true

class InstallationDeleteProcessor < ApplicationProcessor
  group_name "installation_delete"
  handle_topic(/github\.v1\.IntegrationInstallationDelete\Z/, InstallationDeleteHandler)
end
