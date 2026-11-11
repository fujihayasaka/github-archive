# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MigrationSourceType < Platform::Enums::Base
      docs_category :migrations
      description "Represents the different GitHub Enterprise Importer (GEI) migration sources."

      value "AZURE_DEVOPS", "An Azure DevOps migration source.", value: :CONNECTOR_INSTANCE_TYPE_AZURE_DEVOPS
      value "BITBUCKET_SERVER", "A Bitbucket Server migration source.", value: :CONNECTOR_INSTANCE_TYPE_BITBUCKET_SERVER
      value "GITHUB_ARCHIVE", "A GitHub Migration API source.", value: :CONNECTOR_INSTANCE_TYPE_GITHUB_ARCHIVE
      value "GL_EXPORTER_ARCHIVE", "A GitLab Exporter Archive migration source.", value: :CONNECTOR_INSTANCE_TYPE_GL_EXPORTER_ARCHIVE, feature_flag: :octoshift_gl_exporter
      value "GITLAB", "A GitLab migration source.", value: :CONNECTOR_INSTANCE_TYPE_GITLAB, feature_flag: :octoshift_ll_gitlab_self_serve
    end
  end
end
