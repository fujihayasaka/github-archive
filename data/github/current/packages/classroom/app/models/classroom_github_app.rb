# typed: true
# frozen_string_literal: true

module ClassroomGitHubApp
  class RepositoryWriteAccessCheck
    include ActiveModel::Model
    attr_accessor :installation_id, :starter_code_repository_id

    ALLOWED_CLASSROOM_INTEGRATION_SLUGS = %w[github-classroom github-classroom-staging].freeze

    validate :integration_allowed
    validate :integration_can_create_repo
    validate :starter_repo_within_disk_threshold, if: :starter_repo
    validate :integration_can_access_starter_repo, if: :starter_repo

    def installation
      @installation ||= IntegrationInstallation.find_by!(id: installation_id)
    end

    def starter_repo
      @starter_repo ||= Repository.find_by(id: starter_code_repository_id)
    end

    def org
      installation.target
    end

    def renderable_error
      errors.full_messages.join(", ")
    end

    private

    def integration_allowed
      errors.add(:installation, "does not have permission to access") unless ALLOWED_CLASSROOM_INTEGRATION_SLUGS.include?(installation.integration.slug)
    end

    def integration_can_create_repo
      errors.add(:installation, "does not have permission to create repos") unless installation.permissions["administration"] == :write
    end

    def starter_repo_within_disk_threshold
      errors.add(:starter_repo, "is too large") if starter_repo.disk_usage > ClassroomRepository::MAX_STARTER_REPO_DISK_USAGE_IN_KILOBYTES.kilobytes
    end

    def integration_can_access_starter_repo
      unless starter_repo.resources&.contents&.readable_by?(installation)
        errors.add(:starter_repo, "must be readable by installation")
      end
    end
  end
end
