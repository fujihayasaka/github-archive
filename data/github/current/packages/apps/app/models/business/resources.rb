# typed: true
# frozen_string_literal: true

class Business::Resources < Permissions::FineGrainedResource
  # Internal: Which business resources are publicly available.
  PUBLIC_SUBJECT_TYPES = %w(
  ).freeze

  # Internal: Which business resources are available but not publicized.
  PRIVATE_SUBJECT_TYPES = %w(
    enterprise_vulnerabilities
    enterprise_administration
    test_subject_for_required_permissions
  ).freeze

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
  PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = {
    "enterprise_organization_installations" => :enterprise_app_installation_management,
    "enterprise_organization_installation_repositories" => :enterprise_app_installation_management,
  }.freeze
  # Internal: Which business resources are under a preview feature flag.
  PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

  # Internal: Which business resources are only available in Enterprise.
  ENTERPRISE_SUBJECT_TYPES = %w(
    user_provisioning
  ).freeze

  # Internal: Which business resources can an IntegrationInstallation be
  # granted permission on.
  SUBJECT_TYPES = if GitHub.enterprise?
    PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
  else
    PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES
  end

  WRITEONLY_SUBJECT_TYPES = %w(
    user_provisioning
  )

  EXCLUDED_SUBJECT_TYPES_FOR_TYPE = {
    UserProgrammaticAccess => %w(
      enterprise_organization_installations
      enterprise_organization_installation_repositories
    ),
  }.freeze

  ABILITY_TYPE_PREFIX = "Business"
end
