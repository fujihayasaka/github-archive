# typed: true
# frozen_string_literal: true

class PullRequest
  class Resources < Permissions::FineGrainedResource
    # Internal: Which pull request resources are publicly available.
    PUBLIC_SUBJECT_TYPES = GitHub.public_fine_grained_resources("pull_request").freeze

    # Internal: Pull Request resources which are under preview,
    # and their corresponding feature flag.
    #
    # Anything that should *not* be surfaced to the public
    # should be included here.
    #
    #  Examples
    #
    #   { "sarifs" => :pr_code_scanning_analysis }
    #
    # Returns a Hash.
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = GitHub.preview_fine_grained_resources("pull_request").freeze

    # Internal: Which pull request resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which pull request resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = GitHub.enterprise_fine_grained_resources("pull_request").freeze

    # Internal: Which pull request resources can an OauthAuthorization be
    # granted permission on.
    SUBJECT_TYPES = if GitHub.enterprise?
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
    else
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES
    end

    ABILITY_TYPE_PREFIX = "PullRequest"

    WRITEONLY_SUBJECT_TYPES = GitHub.writeonly_fine_grained_resources("pull_request").freeze
  end
end
