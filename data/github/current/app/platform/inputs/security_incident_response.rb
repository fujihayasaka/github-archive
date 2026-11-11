# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityIncidentResponse < Platform::Inputs::Base
      docs_category :meta
      description "Specifies a user and optional extra data for incident remediations. See argument list for possible remediations."
      visibility :internal

      argument :user_id, ID, "Global Relay ID of a User account.", required: false
      argument :users, [Inputs::SecurityIncidentUser], "Database ID and notification template data for Users.", required: false
      argument :notify, Inputs::SecurityIncidentNotification, "Fields for sending a notification. Excluding this means no notifications are sent.", required: false
      argument :staffnote, String, "Optional staffnote text", required: false

      # Available Remediations
      # Delete_issues is hard deleting user data and can be reversed only by manually restoring from backup. Please use with caution.
      argument :delete_issues, [Platform::Scalars::BigInt], "A list of this user's issue database IDs to delete.", required: false
      # delete_issue_comments is hard deleting user data and can be reversed only by manually restoring from backup. Please use with caution.
      argument :delete_issue_comments, [Platform::Scalars::BigInt], "A list of this user's issue comment database IDs to delete.", required: false
      argument :remove_repository_recommendations, [Platform::Scalars::BigInt], "A list of Repository database IDs to opt out of being recommended to other users.", required: false
      argument :remove_repository_stars, [Platform::Scalars::BigInt], "A list of Repository database IDs to remove this user's stars from.", required: false
      argument :reset_password, Boolean, "Reset this user's password?", required: false, default_value: false
      argument :revoke_oauth_authorizations, [Platform::Scalars::BigInt], "A list of OAuth Application database IDs to revoke authorizations for", required: false
      argument :revoke_oauth_tokens, [Platform::Scalars::BigInt], "A list of OAuth Access/Personal Access Token database IDs to revoke", required: false
      argument :revoke_fine_grained_tokens, [Platform::Scalars::BigInt], "A list of Fine Grained Token database IDs to revoke", required: false
      argument :revoke_all_oauth_tokens, Boolean, "Revoke all of this user's classic Personal Access Tokens and GitHub App authorizations. First-party and third-party OAuth Application authorizations are not affected; use revokeAllOauthAuthorizations for third-party OAuth Apps.", required: false, default_value: false
      argument :revoke_all_oauth_authorizations, Boolean, "Revoke all of this user's third-party OAuth Application authorizations.", required: false, default_value: false
      argument :revoke_all_fine_grained_tokens, Boolean, "Revoke all of this user's fine-grained personal access tokens.", required: false, default_value: false
      argument :suspend, String, "Suspend this user with this argument as the reason.", required: false
      argument :set_screening_status, Inputs::SecurityIncidentScreeningStatus, "Set this user's screening status and status change reason.", required: false
      argument :sdn_manual_screening, Boolean, "Manually screen this user", required: false, default_value: false
      argument :sdn_suspend, String, "SDN suspend this account with this argument as the reason.", required: false
      argument :sdn_unsuspend, String, "SDN unsuspend this account with this argument as the reason.", required: false
    end
  end
end
