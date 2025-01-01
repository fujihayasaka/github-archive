# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class SwitchProfilesComponent < ApplicationComponent
      attr_reader :profile_layout_data, :align_right, :has_pinned_items, :any_pinnable_items, :viewer_can_change_pinned_items, :dialog_location

      delegate(
        :profile_organization,
        to: :profile_layout_data,
      )

      VIEW_AS = { "public" => "Public", "member" => "Member" }.freeze

      def initialize(profile_layout_data:, align_right:, dialog_location: nil)
        @profile_layout_data = profile_layout_data
        @align_right = align_right
        @item_showcase = profile_layout_data.item_showcase
        @has_pinned_items = @item_showcase&.has_pinned_items?
        @any_pinnable_items = profile_layout_data.any_pinnable_items
        @viewer_can_change_pinned_items = profile_layout_data.viewer_can_change_pinned_items
        @dialog_location = dialog_location
      end

      # https://github.com/github/special-projects/issues/866#issuecomment-1028692951
      # render for org members only in dotcom or enterprise.
      def render?
        org_profile_switcher_enabled?
      end

      def org_profile_switcher_enabled?
        helpers.show_profile_toggle?(profile_organization)
      end

      def profile_readme
        profile_layout_data.org_profile_readme&.readme
      end

      def profile_repository
        profile_layout_data.org_profile_readme&.repository
      end

      # When no selection defaults to public profile.
      memoize def selected_view_as
        get_selected_view_as
      end

      memoize def sub_heading_copy
        get_copy_text_for_view_as
      end

      def add_readme_param
        viewing_as_member? ? "org_member_profile_readme" : "org_profile_readme"
      end

      def profile_readme_param
        "visibility=#{visibility}&name=#{repo_name}"
      end

      memoize def should_display_cta?
        should_display_readme_cta? || should_display_pins_cta?
      end

      # Not all org members can create repositories.
      # https://docs.github.com/organizations/managing-organization-settings/restricting-repository-creation-in-your-organization
      memoize def should_display_readme_cta?
        (!profile_repository.present? && profile_layout_data.profile_organization.can_create_repository?(
              profile_layout_data.viewer,
              visibility: visibility)) ||
            (profile_repository.present? && !profile_readme.present? && profile_repository.pushable_by?(profile_layout_data.viewer))
      end

      memoize def should_display_pins_cta?
        # Does the user have org admin access to able to pin repos? (viewer_can_change_pinned_items)
        # Are there any repos to pin? (any_pinnable_items)
        # Are there already pinned repos? (has_pinned_items)
        viewer_can_change_pinned_items && any_pinnable_items && !has_pinned_items
      end

      def visible_text
        viewing_as_member? ? "visible only to members of the organization" : "visible to anyone"
      end

      def visibility
        viewing_as_member? ? "private" : "public"
      end

      def repo_name
        viewing_as_member? ? ".github-private" : ".github"
      end

      private

      def get_copy_text_for_view_as
        if viewing_as_member?
          "You are viewing the README and pinned repositories as a member of the #{profile_layout_data.profile_organization.safe_profile_name} organization."
        else
          "You are viewing the README and pinned repositories as a public user."
        end
      end

      def viewing_as_member?
        profile_layout_data.view_as == "member"
      end

      def get_selected_view_as
        VIEW_AS[profile_layout_data.view_as] || VIEW_AS["public"]
      end
    end
  end
end
