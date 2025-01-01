# typed: true
# frozen_string_literal: true

class Organization
  class Resources < Permissions::FineGrainedResource
    # Internal: Which organization resources are publicly available.
    PUBLIC_SUBJECT_TYPES = %w(
      members
      organization_user_blocking
      organization_projects
      team_discussions
      organization_actions_variables
      organization_administration
      organization_announcement_banners
      organization_codespaces_secrets
      organization_codespaces
      organization_codespaces_settings
      organization_copilot_seat_management
      organization_custom_properties
      organization_custom_org_roles
      organization_custom_roles
      organization_dependabot_secrets
      organization_events
      organization_hooks
      organization_plan
      organization_secrets
      organization_self_hosted_runners
      organization_personal_access_tokens
      organization_personal_access_token_requests
    ).freeze

    # Internal: Which organization resources are available but not publicized.
    PRIVATE_SUBJECT_TYPES = %w(
      enterprise_vulnerabilities
      organization_packages
    ).freeze

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
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = {
      "issue_types" => :issue_types,
      "organization_network_configurations" => :actions_network_configuration_api,
      "organization_knowledge_bases" => :copilot_org_knowledge_bases_api,
    }.freeze

    # Internal: Which organization resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which organization resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = %w(organization_pre_receive_hooks).freeze

    # Internal: Which organization resources can an IntegrationInstallation be
    # granted permission on.
    SUBJECT_TYPES = if GitHub.enterprise?
      PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
    else
      PUBLIC_SUBJECT_TYPES + PRIVATE_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES
    end

    ABILITY_TYPE_PREFIX = "Organization"

    READONLY_SUBJECT_TYPES = %w(
      organization_events
      organization_plan
    ).freeze

    ADMINABLE_SUBJECT_TYPES = %w(
      organization_custom_properties
      organization_projects
    ).freeze

    EXCLUDED_SUBJECT_TYPES_FOR_TYPE = {
      Integration => %w(),
      UserProgrammaticAccess => %w(organization_personal_access_tokens organization_personal_access_token_requests),
    }.freeze
  end
end
