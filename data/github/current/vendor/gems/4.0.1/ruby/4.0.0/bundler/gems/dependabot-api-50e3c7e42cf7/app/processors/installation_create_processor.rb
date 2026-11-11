# frozen_string_literal: true

class InstallationCreateProcessor < ApplicationProcessor
  group_name "installation_create"
  handle_topic(/github\.v1\.IntegrationInstallationCreate\Z/, InstallationCreateHandler)
end
