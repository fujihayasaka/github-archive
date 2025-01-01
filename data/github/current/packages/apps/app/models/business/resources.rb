# typed: true
# frozen_string_literal: true

class Business::Resources < Permissions::FineGrainedResource
  # Internal: Which business resources are publicly available.
  PUBLIC_SUBJECT_TYPES = GitHub.public_fine_grained_resources("business").freeze

  # Internal: Which business resources are available but not publicized.
  PRIVATE_SUBJECT_TYPES = GitHub.private_fine_grained_resources("business").freeze

  # Internal: Business resources which are under preview,
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
  PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = GitHub.preview_fine_grained_resources("business").freeze

  # Internal: Which business resources are under a preview feature flag.
  PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

  # Internal: Which business resources can an IntegrationInstallation be
  # granted permission on.
  SUBJECT_TYPES = PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES

  WRITEONLY_SUBJECT_TYPES = GitHub.writeonly_fine_grained_resources("business").freeze

  ADMINABLE_SUBJECT_TYPES = GitHub.adminable_fine_grained_resources("business").freeze

  EXCLUDED_SUBJECT_TYPES_FOR_TYPE = GitHub.excluded_actors_fine_grained_resources("business").freeze

  ABILITY_TYPE_PREFIX = "Business"

  EXTRA_FEATURE_FLAG_DEPENDENCIES = GitHub.extra_feature_flag_dependencies("business").freeze
end
