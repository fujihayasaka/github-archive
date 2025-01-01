# typed: true
# frozen_string_literal: true

class Organization
  class Resources < Permissions::FineGrainedResource
    # Internal: Which organization resources are publicly available.
    PUBLIC_SUBJECT_TYPES = GitHub.public_fine_grained_resources("organization").freeze

    # Internal: Which organization resources are available but not publicized.
    PRIVATE_SUBJECT_TYPES = GitHub.private_fine_grained_resources("organization").freeze

    # Internal: Organization resources which are under preview,
    # and their corresponding feature flag.
    #
    # Anything that should *not* be surfaced to the public
    # should be included here.
    #
    #  Examples
    #
    #   { "teams" => :dat_feature_flag_name }
    #
    # Returns a Hash.
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = GitHub.preview_fine_grained_resources("organization").freeze

    # Internal: Which organization resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which organization resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = GitHub.enterprise_fine_grained_resources("organization").freeze

    # Internal: Which organization resources can an IntegrationInstallation be
    # granted permission on.
    SUBJECT_TYPES = if GitHub.enterprise?
      PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
    else
      PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES
    end

    ABILITY_TYPE_PREFIX = "Organization"

    READONLY_SUBJECT_TYPES = GitHub.readonly_fine_grained_resources("organization").freeze

    ADMINABLE_SUBJECT_TYPES = GitHub.adminable_fine_grained_resources("organization").freeze

    EXCLUDED_SUBJECT_TYPES_FOR_TYPE = GitHub.excluded_actors_fine_grained_resources("organization").freeze
  end
end
