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

    # Internal: Which pull request resources can an fine-grained programmatic actor be
    # granted permission on.
    SUBJECT_TYPES = PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES

    ABILITY_TYPE_PREFIX = "PullRequest"

    WRITEONLY_SUBJECT_TYPES = GitHub.writeonly_fine_grained_resources("pull_request").freeze

    EXTRA_FEATURE_FLAG_DEPENDENCIES = GitHub.extra_feature_flag_dependencies("pull_request").freeze
  end
end
