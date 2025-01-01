# typed: true
# frozen_string_literal: true

class Repository
  class Resources < Permissions::FineGrainedResource
    # Internal: Which repository resources are publicly available.
    PUBLIC_SUBJECT_TYPES = %w(
      actions
      actions_variables
      administration
      attestations
      checks
      contents
      codespaces
      codespaces_lifecycle_admin
      codespaces_metadata
      codespaces_secrets
      dependabot_secrets
      deployments
      discussions
      environments
      issues
      merge_queues
      metadata
      pages
      packages
      pull_requests
      repository_advisories
      repository_custom_properties
      repository_hooks
      repository_projects
      secrets
      secret_scanning_alerts
      security_events
      vulnerability_alerts
      single_file
      statuses
      workflows
    ).freeze

    # Internal: Repository resources which are under preview,
    # and their corresponding feature flag.
    #
    # Anything that should *not* be surfaced to the public
    # should be included here.
    #
    #  Examples
    #
    #   { "checks" => :dat_feature_flag_name }
    #
    # Returns a Hash.
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = {
      "pull_requests_from_forks" => :pull_requests_from_forks_resource,
      "pull_requests_comment_only_reviews" => :pull_requests_comment_only_reviews_resource,
      "repository_announcement_banners" => :enterprise_banners_repo_level,
    }.freeze
    # Internal: Which repository resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which repository resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = %w(repository_pre_receive_hooks).freeze

    # Internal: Which repository resources can an IntegrationInstallation be
    # granted permission on.
    SUBJECT_TYPES = if GitHub.enterprise?
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
    else
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES
    end

    # Internal: Which repository resources does an IntegrationInstallation get
    # access on, by default
    DEFAULT_PERMISSIONS = {}.freeze

    ABILITY_TYPE_PREFIX = "Repository"
    INDIVIDUAL_ABILITY_TYPE_PREFIX = ABILITY_TYPE_PREFIX
    ALL_ABILITY_TYPE_PREFIX = "User/repositories"

    READONLY_SUBJECT_TYPES = %w(
      metadata
      codespaces_metadata
    ).freeze

    WRITEONLY_SUBJECT_TYPES = %w(
      workflows
      pull_requests_from_forks
      pull_requests_comment_only_reviews
      codespaces_secrets
    )

    ADMINABLE_SUBJECT_TYPES = %w(
      repository_projects
    ).freeze

    AUTHZD_SUBJECT_TYPES = %w(
      contents
      metadata
      pull_requests
    ).freeze

    EXCLUDED_SUBJECT_TYPES_FOR_TYPE = {
      Integration => %w(),
      UserProgrammaticAccess => %w(single_file checks packages repository_projects),
    }.freeze

    def authzd_enabled?(action, subject_type)
      AUTHZD_SUBJECT_TYPES.include?(subject_type)
    end

    # Public: interface for access control to a specific file
    #
    # path - The String of the content path to check access to, within a given repository.
    def file(path)
      IntegrationInstallation::SingleFile.new(repository: repository, path: path)
    end
  end
end
