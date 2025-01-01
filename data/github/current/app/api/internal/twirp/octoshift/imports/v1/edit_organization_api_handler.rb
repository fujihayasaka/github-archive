# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditOrganizationAPIService
      class EditOrganizationAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::LiveMigrations

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditOrganizationAPIService

        # Public: Implementation of the EditOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditOrganizationResponse, or a Twirp::Error.
        def edit_organization(req, env)
          check_model_replication_delay!(Organization)
          check_model_replication_delay!(UserLabel)

          begin
            org = Organization.find_by(id: req.organization_id)
          rescue ActiveRecord::RecordNotFound
            return Twirp::Error.not_found("Organization not found.", argument: "organization_id", value: req.organization_id.to_s)
          end

          err = check_outdated_updated_at(org, req.updated_at)
          return err if err

          edit_errors = []

          # Update Org Admins
          edit_errors += ActiveRecord::Base.connected_to(role: :writing) do
            edit_org_admins(org, req.user_ids)
          end

          # Update member privileges
          edit_errors += ActiveRecord::Base.connected_to(role: :writing) do
            edit_member_privileges(org, req.member_privileges)
          end

          # Update repository defaults
          edit_errors += ActiveRecord::Base.connected_to(role: :writing) do
            edit_repository_default(org, req.repository_default)
          end

          edit_errors.flatten!
          if edit_errors.any?
            raise Errors::UnableToEditError, Twirp::Error.canceled(edit_errors.join("\n"))
          end

          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def edit_org_admins(org, req_user_ids)
          current_admins = org.admin_ids
          new_admins = req_user_ids

          errors = []
          admins_to_add = new_admins - current_admins #remove any admins that are already present
          admins_to_remove = current_admins - new_admins # remove any admins that are no longer present

          # Replace the admins by adding first then removing.
          admins_to_add.each do |user_id|
            user = User.find_by(id: user_id)
            errors << Twirp::Error.not_found("User not found.", argument: "user_id", value: user_id) unless user
            next unless user

            # If the user is already a direct member, update their role to admin.
            # Otherwise, add an error that they need to be added to the org.
            if org.direct_member?(user)
              org.update_member(user, action: :admin, updater: org.owner)

              errors << "Failed to add organization admin privileges for user #{user.login}." unless org.adminable_by?(user)
            else
              errors << "User #{user.login} is not a member of #{org.login}"
            end
          end

          admins_to_remove.each do |admin_id|
            user = User.find_by(id: admin_id)
            errors << Twirp::Error.not_found("User not found.", argument: "user_id", value: admin_id) unless user
            next unless user

            org.update_member(user, action: :read, updater: org.owner)

            errors << "Failed to remove organization admin privileges for user #{user.login}." if org.adminable_by?(user)
          end

          errors
        end

        def edit_member_privileges(org, req)
          edit_errors = []

          edit_errors << edit_default_repository_permission(org, req.default_repository_permission&.value)
          edit_errors << edit_members_can_create_repository_with_visibilities(org, req)
          edit_errors << edit_members_can_invite_outside_collaborators(org, req.members_can_invite_outside_collaborators&.value)
          edit_errors << edit_allows_private_repository_forking(org, req.allows_private_repository_forking&.value)
          edit_errors << edit_members_can_create_pages(org, req.members_can_create_pages&.value)
          edit_errors << edit_members_can_change_repo_visibility(org, req.members_can_change_repo_visibility&.value)
          edit_errors << edit_members_can_delete_repositories(org, req.members_can_delete_repositories&.value)
          edit_errors << edit_members_can_delete_issues(org, req.members_can_delete_issues&.value)
          edit_errors << edit_display_commenter_full_name(org, req.display_commenter_full_name_setting_enabled&.value)
          edit_errors << edit_readers_can_create_discussions(org, req.readers_can_create_discussions&.value)
          edit_errors << edit_members_can_create_teams(org, req.members_can_create_teams&.value)
          edit_errors << edit_members_can_view_dependency_insights(org, req.members_can_view_dependency_insights&.value)

          edit_errors.compact
        end

        def edit_repository_default(org, req)
          edit_errors = []

          edit_errors << edit_default_repository_branch(org, req.repository_default_branch&.value)
          edit_errors << edit_commit_signoff(org, req.commit_signoff&.value)
          edit_org_labels(org, req.labels)

          edit_errors
        end

        # Edit Member Privileges Sub-Methods
        def edit_default_repository_permission(org, default_repository_permission)
          return if org.default_repository_permission_name == default_repository_permission

          begin
            org.update_default_repository_permission(
              default_repository_permission,
              actor: org.owner
            )
            edited = org.default_repository_permission_name == default_repository_permission
            "Failed to update default repository permission to #{default_repository_permission}." unless edited
          rescue Configurable::DefaultRepositoryPermission::AlreadyUpdating
            "Default repository permission is already being updated."
          end
        end

        def edit_members_can_create_repository_with_visibilities(org, req)
          org.allow_members_can_create_repositories_with_visibilities(
            actor: org.owner,
            public_visibility: req.members_can_create_public_repositories&.value,
            private_visibility: req.members_can_create_private_repositories&.value,
            internal_visibility: req.members_can_create_internal_repositories&.value
          )

          errors = []
          [:public, :private, :internal].each do |visibility|
            edited = org.send("members_can_create_#{visibility}_repositories?") == req.send("members_can_create_#{visibility}_repositories")&.value
            errors << "Members can create #{visibility} repositories setting could not be edited" unless edited
          end

          errors
        end

        def edit_members_can_invite_outside_collaborators(org, req_members_can_invite_outside_collaborators)
          return if org.members_can_invite_outside_collaborators? == req_members_can_invite_outside_collaborators

          if req_members_can_invite_outside_collaborators
            org.allow_members_can_invite_outside_collaborators(actor: org.owner)
          else
            org.disallow_members_can_invite_outside_collaborators(actor: org.owner)
          end

          edited = org.members_can_invite_outside_collaborators? == req_members_can_invite_outside_collaborators
          "Members can invite outside collaborators setting could not be edited to #{req_members_can_invite_outside_collaborators} " unless edited
        end

        def edit_allows_private_repository_forking(org, req_allows_private_repository_forking)
          return if org.allow_private_repository_forking? == req_allows_private_repository_forking
          # Check first if forking is disabled at the enterprise level
          if private_repository_forking_disabled_for_org?(org) && req_allows_private_repository_forking
            return "Cannot update setting: Private repository forking is disabled for this organization due to enterprise policies."
          end

          if req_allows_private_repository_forking
            org.allow_private_repository_forking(actor: org.owner)
          else
            org.block_private_repository_forking(actor: org.owner)
          end

          edited = org.allow_private_repository_forking? == req_allows_private_repository_forking
          "Allows private repository forking setting could not be edited to #{req_allows_private_repository_forking}" unless edited
        end

        def private_repository_forking_disabled_for_org?(organization)
          if organization.supports_enhanced_enterprise_forking_policies?
            forking_disabled_by_enterprise = organization.business&.allow_private_repository_forking_policy? && !organization.business.allow_private_repository_forking?
            return forking_disabled_by_enterprise
          end

          organization&.business&.allow_private_repository_forking_policy?
        end

        def edit_members_can_create_pages(org, req_members_can_create_pages)
          return if org.members_can_create_pages? == req_members_can_create_pages

          org.update_members_create_pages_permission(enabled: req_members_can_create_pages, actor: org.owner)

          edited = org.members_can_create_pages? == req_members_can_create_pages
          "Members can create pages setting could not be edited to #{req_members_can_create_pages}" unless edited
        end

        def edit_members_can_change_repo_visibility(org, req_members_can_change_repo_visibility)
          return if org.members_can_change_repo_visibility? == req_members_can_change_repo_visibility

          if req_members_can_change_repo_visibility
            org.allow_members_to_change_repo_visibility(actor: org.owner)
          else
            org.block_members_from_changing_repo_visibility(actor: org.owner)
          end

          edited = org.members_can_change_repo_visibility? == req_members_can_change_repo_visibility
          "Members can change repository visibility setting could not be edited to #{req_members_can_change_repo_visibility}" unless edited
        end

        def edit_members_can_delete_repositories(org, req_members_can_delete_repositories)
          return if org.members_can_delete_repositories? == req_members_can_delete_repositories

          if req_members_can_delete_repositories
            org.allow_members_can_delete_repositories(actor: org.owner)
          else
            org.disallow_members_can_delete_repositories(actor: org.owner)
          end

          edited = org.members_can_delete_repositories? == req_members_can_delete_repositories
          "Members can delete repositories setting could not be edited to #{req_members_can_delete_repositories}" unless edited
        end

        def edit_members_can_delete_issues(org, req_members_can_delete_issues)
          return if org.members_can_delete_issues? == req_members_can_delete_issues
          if req_members_can_delete_issues
            org.allow_members_can_delete_issues(actor: org.owner)
          else
            org.disallow_members_can_delete_issues(actor: org.owner)
          end

          edited = org.members_can_delete_issues? == req_members_can_delete_issues
          "Members can delete issues setting could not be edited to #{req_members_can_delete_issues}" unless edited
        end

        def edit_display_commenter_full_name(org, req_display_commenter_full_name)
          return if org.display_commenter_full_name_setting_enabled? == req_display_commenter_full_name

          if req_display_commenter_full_name
            org.enable_display_commenter_full_name(actor: org.owner)
          else
            org.disable_display_commenter_full_name(actor: org.owner)
          end

          edited = org.display_commenter_full_name_setting_enabled? == req_display_commenter_full_name
          "Display commenter full name setting could not be edited to #{req_display_commenter_full_name}" unless edited
        end

        def edit_readers_can_create_discussions(org, req_readers_can_create_discussions)
          return if org.readers_can_create_discussions? == req_readers_can_create_discussions

          if req_readers_can_create_discussions
            org.allow_readers_to_create_discussions(actor: org.owner)
          else
            org.block_readers_from_creating_discussions(actor: org.owner)
          end

          edited = org.readers_can_create_discussions? == req_readers_can_create_discussions
          "Readers can create discussions setting could not be edited to #{req_readers_can_create_discussions}" unless edited
        end

        def edit_members_can_create_teams(org, req_members_can_create_teams)
          return if org.members_can_create_teams? == req_members_can_create_teams

          if req_members_can_create_teams
            org.allow_members_to_create_teams(actor: org.owner)
          else
            org.block_members_from_creating_teams(actor: org.owner)
          end

          edited = org.members_can_create_teams? == req_members_can_create_teams
          "Members can create teams setting could not be edited to #{req_members_can_create_teams}" unless edited
        end

        def edit_members_can_view_dependency_insights(org, req_members_can_view_dependency_insights)
          return if org.members_can_view_dependency_insights? == req_members_can_view_dependency_insights

          if req_members_can_view_dependency_insights
            org.allow_members_can_view_dependency_insights(actor: org.owner)
          else
            org.disallow_members_can_view_dependency_insights(actor: org.owner)
          end

          edited = org.members_can_view_dependency_insights? == req_members_can_view_dependency_insights
          "Members can view dependency insights setting could not be edited to #{req_members_can_view_dependency_insights}" unless edited
        end

        # Edit Repository Defaults Sub-Methods

        def edit_default_repository_branch(org, req_repository_default_branch)
          return if org.default_new_repo_branch == req_repository_default_branch

          edited = org.set_default_new_repo_branch(req_repository_default_branch, actor: org.owner)
          "Failed to update default repository default branch name to #{req_repository_default_branch}" unless edited
        end

        def edit_commit_signoff(org, req_commit_signoff)
          return if org.dco_signoff_enabled? == req_commit_signoff

          if req_commit_signoff
            org.enable_dco_signoff_for_all(actor: org.owner)
          else
            org.reset_dco_signoff_for_all(actor: org.owner)
          end

          edited = org.dco_signoff_enabled? == req_commit_signoff
          "Failed to update web commit signoff requirement to #{req_commit_signoff}." unless edited
        end

        def edit_org_labels(org, request_labels)
          desired_label_names = request_labels.map(&:name).map(&:strip)
          desired_label_properties = request_labels.map do |label|
            {
              name: label.name.strip,
              color: label.color.strip,
              description: label.description.strip
            }
          end

          desired_labels = Set[*desired_label_properties]

          existing_label_names = org.user_labels.pluck(:name).map(&:strip)
          existing_label_properties = org.user_labels.pluck(:name, :color, :description).map do |name, color, desc|
            {
              name: name.strip,
              color: color.strip,
              description: desc.strip
            }
          end

          existing_labels = Set[*existing_label_properties]

          labels_to_upsert = desired_labels - existing_labels
          labels_to_delete = existing_label_names - desired_label_names

          labels_to_upsert.each do |label|
            if existing_label = org.user_labels.find_by(name: label[:name])
              existing_label.update!(
                color: label[:color] || generate_sample_color,
                description: label[:description]
              )
            else
              org.user_labels.create!(
                name: label[:name],
                color: label[:color] || generate_sample_color,
                description: label[:description]
              )
            end
          end

          org.user_labels.where(name: labels_to_delete).destroy_all
        end

        def generate_sample_color
          Label.defaults.sample.color
        end

        def edit_org_settings_hash(org, edit_errors = [])
          {}
        end
      end
    end
  end
end
