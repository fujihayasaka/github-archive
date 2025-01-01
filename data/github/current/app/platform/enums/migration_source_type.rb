# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MigrationSourceType < Platform::Enums::Base
      description "Represents the different GitHub Enterprise Importer (GEI) migration sources."

      value "AZURE_DEVOPS", "An Azure DevOps migration source.", value: :CONNECTOR_INSTANCE_TYPE_AZURE_DEVOPS
      value "BITBUCKET_SERVER", "A Bitbucket Server migration source.", value: :CONNECTOR_INSTANCE_TYPE_BITBUCKET_SERVER
      value "GITHUB_ARCHIVE", "A GitHub Migration API source.", value: :CONNECTOR_INSTANCE_TYPE_GITHUB_ARCHIVE
      value "GL_EXPORTER_ARCHIVE", "A GitLab Exporter Archive migration source.", value: :CONNECTOR_INSTANCE_TYPE_GL_EXPORTER_ARCHIVE, feature_flag: :octoshift_gl_exporter
    end
  end
end
