# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationSettingsAPIService
      class ImportOrganizationSettingsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationSettingsAPIService

        # Public: Implementation of the ImportOrganizationSettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationSettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportOrganizationSettingsResponse, or a Twirp::Error.
        def import_organization_settings(req, env)
          check_model_replication_delay!(UserLabel)
          check_model_replication_delay!(Organization)

          unless req.target_org_id.positive?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "target_org_id")
          end

          organization = replica(Organization).find_by(id: req.target_org_id)
          return Twirp::Error.not_found("organization not found", argument: "target_org_id", value: req.target_org_id.to_s) unless organization

          settings_errors = ActiveRecord::Base.connected_to(role: :writing) do
            update_member_privileges(organization, req.member_privileges)
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            settings_errors += create_webhooks(organization, req.webhooks) if req.webhooks.present?
            settings_errors += update_repository_default(organization, req.repository_default)
          end

          organization_settings_hash(organization, settings_errors)
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def update_member_privileges(organization, member_privileges)
          settings_errors = []

          if member_privileges.default_repository_permission&.present?
            begin
              organization.update_default_repository_permission(
                member_privileges.default_repository_permission&.value,
                actor: organization.owner
              )
            rescue ArgumentError, Configurable::DefaultRepositoryPermission::AlreadyUpdating
              settings_errors << "Default repository permission could not be imported"
            end
          end

          if member_privileges.members_can_invite_outside_collaborators&.present?
            if member_privileges.members_can_invite_outside_collaborators&.value
              organization.allow_members_can_invite_outside_collaborators(actor: organization.owner)
            else
              organization.disallow_members_can_invite_outside_collaborators(actor: organization.owner)
            end

            settings_errors << "Invite outside collaborators permission could not be imported" unless organization.members_can_invite_outside_collaborators? == member_privileges.members_can_invite_outside_collaborators&.value
          end

          if member_privileges.allows_private_repository_forking&.present?
            settings_errors += import_private_repository_forking(member_privileges.allows_private_repository_forking&.value, organization)
          end

          if member_privileges.members_can_create_pages&.present?
            organization.update_members_create_pages_permission(enabled: member_privileges.members_can_create_pages&.value, actor: organization.owner)

            settings_errors << "Create pages permission could not be imported" unless organization.members_can_create_pages? == member_privileges.members_can_create_pages&.value
          end

          if member_privileges.members_can_change_repo_visibility&.present?
            if member_privileges.members_can_change_repo_visibility&.value
              organization.allow_members_to_change_repo_visibility(actor: organization.owner)
            else
              organization.block_members_from_changing_repo_visibility(actor: organization.owner)
            end

            settings_errors << "Change repository visibility permission could not be imported" unless organization.members_can_change_repo_visibility? == member_privileges.members_can_change_repo_visibility&.value
          end

          if member_privileges.members_can_delete_repositories&.present?
            if member_privileges.members_can_delete_repositories&.value
              organization.allow_members_can_delete_repositories(actor: organization.owner)
            else
              organization.disallow_members_can_delete_repositories(actor: organization.owner)
            end

            settings_errors << "Delete repositories permission could not be imported" unless organization.members_can_delete_repositories? == member_privileges.members_can_delete_repositories&.value
          end

          if member_privileges.members_can_delete_issues&.present?
            if member_privileges.members_can_delete_issues&.value
              organization.allow_members_can_delete_issues(actor: organization.owner)
            else
              organization.disallow_members_can_delete_issues(actor: organization.owner)
            end

            settings_errors << "Delete issues permission could not be imported" unless organization.members_can_delete_issues? == member_privileges.members_can_delete_issues&.value
          end

          if member_privileges.display_commenter_full_name_setting_enabled&.present?
            if member_privileges.display_commenter_full_name_setting_enabled&.value
              organization.enable_display_commenter_full_name(actor: organization.owner)
            else
              organization.disable_display_commenter_full_name(actor: organization.owner)
            end

            settings_errors << "Display commenter full name setting could not be imported" unless organization.display_commenter_full_name_setting_enabled? == member_privileges.display_commenter_full_name_setting_enabled&.value
          end

          if member_privileges.readers_can_create_discussions&.present?
            if member_privileges.readers_can_create_discussions&.value
              organization.allow_readers_to_create_discussions(actor: organization.owner)
            else
              organization.block_readers_from_creating_discussions(actor: organization.owner)
            end

            settings_errors << "Readers can create discussions permission could not be imported" unless organization.readers_can_create_discussions? == member_privileges.readers_can_create_discussions&.value
          end

          if member_privileges.members_can_create_teams&.present?
            if member_privileges.members_can_create_teams&.value
              organization.allow_members_to_create_teams(actor: organization.owner)
            else
              organization.block_members_from_creating_teams(actor: organization.owner)
            end

            settings_errors << "Create teams permission could not be imported" unless organization.members_can_create_teams? == member_privileges.members_can_create_teams&.value
          end

          if member_privileges.members_can_view_dependency_insights&.present?
            if member_privileges.members_can_view_dependency_insights&.value
              organization.allow_members_can_view_dependency_insights(actor: organization.owner)
            else
              organization.disallow_members_can_view_dependency_insights(actor: organization.owner)
            end

            settings_errors << "View dependency insights permission could not be imported" unless organization.members_can_view_dependency_insights? == member_privileges.members_can_view_dependency_insights&.value
          end

          settings_errors += import_members_can_create_repositories_with_visibilities(member_privileges, organization)

          settings_errors
        end

        def update_repository_default(organization, repository_default)
          settings_errors = []

          if repository_default.repository_default_branch&.present?
            unless organization.default_new_repo_branch == repository_default.repository_default_branch&.value
              imported = organization.set_default_new_repo_branch(repository_default.repository_default_branch&.value, actor: organization.owner)
              settings_errors << "Repository default branch setting could not be imported" unless imported
            end
          end

          if repository_default.commit_signoff&.present?
            if repository_default.commit_signoff&.value
              organization.enable_dco_signoff_for_all(actor: organization.owner)
            else
              organization.reset_dco_signoff_for_all(actor: organization.owner)
            end

            settings_errors << "Web commit signoff requirement could not be imported" unless organization.dco_signoff_enabled? == repository_default.commit_signoff&.value
          end

          settings_errors += create_labels(organization, repository_default.labels) if repository_default.labels.present?

          settings_errors
        end

        def import_private_repository_forking(private_repository_forking, organization)
          settings_errors = []

          if private_repository_forking_disabled_for_org?(organization)
            if private_repository_forking
              settings_errors << "Repository forking policy must be enabled for the enterprise before enabling at the organization-level"
            else
              organization.block_private_repository_forking(actor: organization.owner)
            end
          else
            if private_repository_forking
              organization.allow_private_repository_forking(actor: organization.owner)
            else
              organization.block_private_repository_forking(actor: organization.owner)
            end

            settings_errors << "Private repository forking permission could not be imported" unless organization.allow_private_repository_forking? == private_repository_forking
          end

          settings_errors
        end

        def private_repository_forking_disabled_for_org?(organization)
          if organization.supports_enhanced_enterprise_forking_policies?
            return false unless organization.business

            forking_disabled_by_enterprise = organization.business.allow_private_repository_forking_policy? && !organization.business.allow_private_repository_forking?
            return forking_disabled_by_enterprise
          end

          organization&.business&.allow_private_repository_forking_policy?
        end

        def import_members_can_create_repositories_with_visibilities(member_privileges, organization)
          organization.allow_members_can_create_repositories_with_visibilities(
            actor: organization.owner,
            public_visibility: member_privileges.members_can_create_public_repositories&.value,
            private_visibility: member_privileges.members_can_create_private_repositories&.value,
            internal_visibility: member_privileges.members_can_create_internal_repositories&.value
          )

          errors = []

          [:public, :private, :internal].each do |visibility|
            imported = organization.send("members_can_create_#{visibility}_repositories?") == member_privileges.send("members_can_create_#{visibility}_repositories")&.value
            errors << "Members can create #{visibility} repositories setting could not be imported" unless imported
          end

          errors
        end

        def create_webhooks(organization, webhooks_req)
          errors = []

          webhooks_req.each do |webhook_req|
            hook = organization.hooks.create(
              name:   "web",
              active: webhook_req.active,
              config: {
                "url"          => webhook_req.payload_url,
                "insecure_ssl" => webhook_req.enable_ssl_verification ? "0" : "1",
                "content_type" => webhook_req.content_type,
              },
              events: webhook_req.event_types & valid_repo_event_types,
              creator_id: organization.id
            )

            errors << "Webhook with url '#{webhook_req.payload_url}' could not be imported" unless hook.save
          end

          errors
        end

        def create_labels(organization, labels_req)
          errors = []

          labels = labels_req.map.with_index do |label_req, _index|
            next if label_exists_with(organization, label_req.name)

            # default to sample color when not specified
            label_color = label_req.color.empty? ? generate_sample_color : label_req.color

            label = organization.user_labels.build(
              name: label_req.name,
              color: label_color,
              description: label_req.description,
              created_at: Time.current,
              updated_at: Time.current
            )

            # Skip invalid labels for now
            if !label.valid?
              errors << "Label with name '#{label_req.name}' could not be imported"
              next
            end

            { "color": label.color }.merge(label.attributes) # re-order hash so the first key isn't a vindex column
          end.compact

          UserLabel.insert_all(labels) if labels.any?

          errors
        end

        def generate_sample_color
          Label.defaults.sample.color
        end

        def valid_repo_event_types
          @valid_repo_event_types ||= Hook::EventRegistry.for_target(Repository).map(&:event_type) + [Hook::WildcardEvent]
        end

        def label_exists_with(organization, label_name)
          replica(UserLabel).query do |klass|
            klass.where(user: organization, name: label_name).exists?
          end
        end

        def organization_settings_hash(organization, settings_errors = [])
          {
            id: organization.id,
            organization_settings_errors: settings_errors
          }
        end
      end
    end
  end
end
