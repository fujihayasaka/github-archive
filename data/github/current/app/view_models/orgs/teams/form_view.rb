# typed: true
# frozen_string_literal: true

module Orgs
  module Teams
    class FormView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :organization
      attr_reader :org # instance of a graphql org which is passed to a child view
      attr_reader :query
      attr_reader :team
      attr_reader :team_entity
      attr_reader :making_new_team
      attr_reader :team_params

      include ActionView::Helpers::TextHelper
      include PlatformHelper

      def initialize(options)
        super(options)

        @team_params = {} if team_params.nil?
      end

      # Public: Should the team name field be autofucused?
      #
      # Returns a boolean.
      def autofocus_name_field?
        making_new_team?
      end

      # Public: Should the submit button be disabled when the view is first
      # loaded?
      #
      # This is true when it's a new team form, because the form will start
      # out blank, which is invalid. Once the user starts typing a name, the
      # client-side validation JS will enable the button.
      #
      # Returns a boolean.
      def disable_submit_button_on_load?
        making_new_team?
      end

      # Public: Get the method to use for the form.
      #
      # Returns a symbol (:post or :put).
      def form_method
        making_new_team? ? :post : :put
      end

      # Public: Get the text to show in the header.
      #
      # Returns a string.
      def header_text
        making_new_team? ? "Create new team" : "Team settings"
      end

      # Public: Should the team delete button be shown?
      #
      # Should only show when editing a non-Owners team.
      #
      # Returns a boolean.
      def show_delete_button?
        editing_existing_team?
      end

      # Public: Should the change permissions button be shown?
      #
      # Should only show when editing a team.
      #
      # Returns a boolean.
      def show_change_permissions_button?
        editing_existing_team?
      end

      def submit_button_text
        making_new_team? ? "Create team" : "Save changes"
      end

      def team_database_id
        team&.id
      end

      def team_name_note
        if making_new_team?
          "You’ll use this name to mention this team in conversations."
        else
          "Changing the team name will break past @mentions."
        end
      end

      def not_deletable?
        team.has_child_teams? && !organization.adminable_by?(current_user)
      end

      def parent_team_id
        if team_params["parentTeam"].present?
          team_params["parentTeam"]["id"]
        elsif team&.parent_team
          team.parent_team.global_relay_id
        elsif requested_parent_team
          requested_parent_team&.global_relay_id
        else
          nil
        end
      end

      def parent_team_name
        if team_params["parentTeam"].present?
          team_params["parentTeam"]["name"]
        elsif team.present? && team.parent_team
          team.parent_team.name
        elsif requested_parent_team
          requested_parent_team_name
        else
          nil
        end
      end

      def team_avatar_url
        team&.primary_avatar_url(400)
      end

      def team_name
        team_params["name"] || team&.name
      end

      def team_combined_slug
        team&.combined_slug
      end

      def team_slug
        team_params["slug"] || original_team_slug
      end

      def team_description
        team_params["description"] || team&.description
      end

      def team_privacy
        team_params["privacy"] || team&.privacy&.upcase
      end

      def team_notification_setting
        team_params["notification_setting"] || team&.notification_setting&.upcase
      end

      def original_team_slug
        team&.slug
      end

      def organization_name
        organization.name
      end

      def page_title_text
        if making_new_team?
          "Create new team · #{organization_name}"
        else
          "Edit #{team_name} team settings · #{organization_name}"
        end
      end

      def original_team_visibility
        team&.privacy
      end

      def team_count
        organization.visible_teams_for(current_user).closed.size
      end

      def allow_team_avatar_uploads?
        !making_new_team
      end

      def show_specific_destruction_warnings
        team.has_child_teams? || discussion_count > 0
      end

      def destruction_warnings
        return unless show_specific_destruction_warnings

        warnings = [
          discussion_count > 0 ? "#{pluralize(discussion_count, "discussion post")}" : nil,
          team.has_child_teams? ? "the following child teams:" : nil,
        ].compact.join(" and ")
        "Deleting this team will delete #{warnings}"
      end

      def current_parent_team
        team&.parent_team || team_params["parentTeam"]
      end

      def requested_parent_team_request
        return unless team
        @_requested_parent_team_request ||= TeamChangeParentRequest.outbound_child_initiated(team).order_by_team_name(:child_team).pending.first
      end

      def requested_parent_team
        requested_parent_team_request&.parent_team
      end

      def requested_parent_team_name
        requested_parent_team&.name
      end

      def legacy_admin_team?
        team&.legacy_admin?
      end

      def enterprise_server_scim_enabled?
        business_sso_configured? && organization.enterprise_server_scim_enabled?
      end

      def show_scim_groups_settings?
        return true if enterprise_server_scim_enabled?
        business_sso_configured? && business_emu_configured?
      end

      def business_emu_configured?
        organization.enterprise_managed_user_enabled?
      end

      def business_sso_configured?
        organization.sso_enabled_on_business?
      end

      def team_can_be_externally_managed?
        if making_new_team?
          organization.show_team_sync_feature?
        else
          team.can_be_externally_managed?
        end
      end

      def externally_managed?
        return false if making_new_team?
        return false unless business_emu_configured? || enterprise_server_scim_enabled?

        team&.externally_managed?
      end

      def enhanced_team_posts_enabled?
        organization.enhanced_team_posts_enabled?
      end

      def team_post_creation_disabled?
        team&.team_post_creation_disabled?
      end

      private

      # Internal: Returns the total count of discussion_posts
      #
      # this doesn't need to scope the count on visibility, as it's only shown
      # when deleting an existing team, so permissions have already been checked
      #
      # Returns an integer
      def discussion_count
        @discussion_count ||= team.discussion_posts.count
      end

      # Internal: Are we editing an existing team rather than making a new one?
      #
      # Returns a boolean.
      def editing_existing_team?
        !making_new_team?
      end

      # Internal: Are we making a new team rather than editing an existing one?
      #
      # Returns a boolean.
      def making_new_team?
        making_new_team
      end
    end
  end
end
