# typed: true
# frozen_string_literal: true

class User
  class Resources < Permissions::FineGrainedResource
    # Internal: Which users resources are publicly available.
    PUBLIC_SUBJECT_TYPES = %w(
      blocking
      codespaces_user_secrets
      emails
      followers
      gists
      git_signing_ssh_public_keys
      gpg_keys
      interaction_limits
      keys
      starring
      plan
      watching
      profile
      private_repository_invitations
    ).freeze

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
    PREVIEW_SUBJECTS_AND_FEATURE_FLAGS = {
      "notifications" => :github_app_user_notifications,
      "copilot_messages" => :copilot_extendable,
      "copilot_editor_context" => :copilot_extendable,
      "knowledge_bases" => :copilot_knowledge_bases_fgp,
    }.freeze

    # Internal: Which user resources are under a preview feature flag.
    PREVIEW_SUBJECT_TYPES = PREVIEW_SUBJECTS_AND_FEATURE_FLAGS.keys

    # Internal: Which user resources are only available in Enterprise.
    ENTERPRISE_SUBJECT_TYPES = %w().freeze

    CONNECT_ONLY_SUBJECT_TYPES = %w(
      external_contributions
    ).freeze

    # Internal: Which users resources can an OauthAuthorization be
    # granted permission on.
    SUBJECT_TYPES = if GitHub.enterprise?
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + CONNECT_ONLY_SUBJECT_TYPES + ENTERPRISE_SUBJECT_TYPES
    else
      PUBLIC_SUBJECT_TYPES + PREVIEW_SUBJECT_TYPES + CONNECT_ONLY_SUBJECT_TYPES
    end

    ABILITY_TYPE_PREFIX = "User"
    ABILITY_COLLECTION_TYPE = OauthAuthorization::AbilityCollection

    READONLY_SUBJECT_TYPES = %w(
      plan
      private_repository_invitations
      copilot_messages
      copilot_editor_context
    ).freeze

    WRITEONLY_SUBJECT_TYPES = %w(
      gists
      profile
    ).freeze

    EXCLUDED_SUBJECT_TYPES_FOR_TYPE = {
      Integration => %w(private_repository_invitations)
    }.freeze
  end
end
