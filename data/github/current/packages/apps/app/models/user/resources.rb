# typed: true
# frozen_string_literal: true

class User
  class Resources < Permissions::FineGrainedResource
    # Internal: Which users resources are publicly available.
    PUBLIC_SUBJECT_TYPES = GitHub.public_fine_grained_resources("user").freeze

    # Internal: User resources which are under preview,
    # and their corresponding feature flag.
    #
    # Anything that should *not* be surfaced to the public
    # should be included here.
    #
    #  Examples
    #
    #   { "emails" => :github_app_user_permissions }
    #
    # Returns a Hash.
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = GitHub.preview_fine_grained_resources("user").freeze

    # Internal: Which user resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which user resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = GitHub.enterprise_fine_grained_resources("user").freeze

    CONNECT_ONLY_SUBJECT_TYPES = GitHub.connectonly_fine_grained_resources("user").freeze

    # Internal: Which users resources can an OauthAuthorization be
    # granted permission on.
    SUBJECT_TYPES = if GitHub.enterprise?
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + CONNECT_ONLY_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
    else
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + CONNECT_ONLY_SUBJECT_TYPES
    end

    ABILITY_TYPE_PREFIX = "User"
    ABILITY_COLLECTION_TYPE = OauthAuthorization::AbilityCollection

    READONLY_SUBJECT_TYPES = GitHub.readonly_fine_grained_resources("user").freeze

    WRITEONLY_SUBJECT_TYPES = GitHub.writeonly_fine_grained_resources("user").freeze

    EXCLUDED_SUBJECT_TYPES_FOR_TYPE = GitHub.excluded_actors_fine_grained_resources("user").freeze
  end
end
