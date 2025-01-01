# typed: true
# frozen_string_literal: true

class Repository
  class Resources < Permissions::FineGrainedResource
    # Internal: Which repository resources are publicly available.
    PUBLIC_SUBJECT_TYPES = GitHub.public_fine_grained_resources("repository").freeze

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
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = GitHub.preview_fine_grained_resources("repository").freeze
    # Internal: Which repository resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which repository resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = GitHub.enterprise_fine_grained_resources("repository").freeze

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

    READONLY_SUBJECT_TYPES = GitHub.readonly_fine_grained_resources("repository").freeze

    WRITEONLY_SUBJECT_TYPES = GitHub.writeonly_fine_grained_resources("repository").freeze

    ADMINABLE_SUBJECT_TYPES = GitHub.adminable_fine_grained_resources("repository").freeze

    AUTHZD_SUBJECT_TYPES = GitHub.authzd_fine_grained_resources("repository").freeze

    EXCLUDED_SUBJECT_TYPES_FOR_TYPE = GitHub.excluded_actors_fine_grained_resources("repository").freeze

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
