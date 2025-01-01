# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class OrganizationSerializer < BaseSerializer
      def scope
        Organization.preload(:profile, :business_membership, :business, :configuration_entries, :user_labels)
      end

      def as_json(options = {})
        {
          type: "organization",
          url: url,
          login: login,
          name: name,
          description: description,
          website: website,
          location: location,
          email: email,
          # members is an N+1 (or worse)
          members: members,
          # owners_team is an N+1
          owners_team: owners_team, # will be deprecated
          webhooks: webhooks,
          created_at: created_at,
          member_privileges: member_privileges,
          repository_defaults: repository_defaults
        }
      end

      private

      def login
        model.login
      end

      def profile
        model.profile
      end

      def name
        profile.name if profile
      end

      def description
        profile.bio if profile
      end

      def website
        profile.blog if profile
      end

      def location
        profile.location if profile
      end

      def email
        if profile && profile.email.present?
          profile.email
        else
          StealthEmail.new(model).email
        end
      end

      def members
        return [] unless actor_can_admin?
        # Skip exporting members when org metadata only, as it's not needed for now.
        return [] if org_metadata_only
        model.members.order(:created_at).map do |user|
          {
            user: url_for_model(user),
            role: model.role_of(user).type,
            state: model.membership_state_of(user),
          }
        end
      end

      def webhooks
        return [] unless actor_can_admin?
        model.hooks.active.map do |webhook|
          {
            payload_url: webhook.url,
            content_type: webhook.content_type,
            event_types: webhook.events,
            enable_ssl_verification: webhook.insecure_ssl == "0",
            active: true,
          }
        end
      end

      def owners_team
      end

      def member_privileges
        {
          default_repository_permission: model.default_repository_permission_name,
          members_can_create_public_repositories: model.members_can_create_public_repositories?,
          members_can_create_private_repositories: model.members_can_create_private_repositories?,
          members_can_create_internal_repositories: model.members_can_create_internal_repositories?,
          members_can_invite_outside_collaborators: model.members_can_invite_outside_collaborators?,
          allows_private_repository_forking: model.allow_private_repository_forking?,
          members_can_create_pages: model.members_can_create_pages?,
          members_can_change_repo_visibility: model.members_can_change_repo_visibility?,
          members_can_delete_repositories: model.members_can_delete_repositories?,
          members_can_delete_issues: model.members_can_delete_issues?,
          display_commenter_full_name_setting_enabled: model.display_commenter_full_name_setting_enabled?,
          readers_can_create_discussions: model.readers_can_create_discussions?,
          members_can_create_teams: model.members_can_create_teams?,
          members_can_view_dependency_insights: model.members_can_view_dependency_insights?
        }
      end

      def repository_defaults
        {
          repository_default_branch: model.default_new_repo_branch,
          commit_signoff: model.dco_signoff_enabled?,
          repository_labels: repository_labels
        }
      end

      def repository_labels
        model.user_labels.map do |label|
          {
            name: label.name,
            description: label.description,
            color: label.color
          }
        end
      end
    end
  end
end
