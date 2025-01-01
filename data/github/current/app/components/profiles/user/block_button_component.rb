# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class BlockButtonComponent < ApplicationComponent

      renders_one :show_button_contents

      def initialize(
        profile_layout_data: nil,
        user: nil,
        viewer_is_sponsoring_user: nil,
        viewer_is_sponsored_by_user: nil,
        viewer_is_blocking_user: nil,
        header_classes: nil,
        dialog_classes: nil,
        show_button_args: {},
        **system_arguments
      )
        @profile_layout_data = profile_layout_data
        @user = user ? user : profile_layout_data&.profile_user
        @viewer_is_sponsoring_user = viewer_is_sponsoring_user
        @viewer_is_sponsored_by_user = viewer_is_sponsored_by_user
        @viewer_is_blocking_user = viewer_is_blocking_user
        @header_classes = header_classes
        @dialog_classes = dialog_classes
        @show_button_args = show_button_args
        @system_arguments = system_arguments
      end

      def render?
        return false if @user.nil? && @profile_layout_data.nil?
        return false if user&.is_enterprise_managed?

        show_block_button?(is_viewer: user_is_viewer?)
      end

      private

      attr_reader :profile_layout_data, :user, :header_classes, :dialog_classes, :show_button_args, :system_arguments

      delegate :show_block_button?, to: :helpers

      memoize def blocking
        unless @viewer_is_blocking_user.nil?
          @blocking = @viewer_is_blocking_user
          return @blocking
        end

        if @profile_layout_data.present?
          profile_layout_data.viewer_blocking_profile_user?
        else
          current_user&.blocking?(user.id)
        end
      end

      memoize def sponsoring?
        if @viewer_is_sponsoring_user.nil?
          user.sponsored_by_viewer?(current_user)
        else
          @viewer_is_sponsoring_user
        end
      end

      memoize def sponsored_by_user?
        @viewer_is_sponsored_by_user.nil? ? current_user&.sponsor_exists_and_is_visible_to?(user.id, viewer: current_user) : @viewer_is_sponsored_by_user
      end

      def user_is_viewer?
        return profile_layout_data.user_is_viewer? unless profile_layout_data.nil?

        @user == current_user
      end

      def blocking_enabled?
        logged_in?
      end

      def btn_class
        "btn-link Link--muted my-2"
      end

      def block_path
        if blocking
          settings_blocked_user_path(user.display_login)
        else
          settings_blocked_users_path
        end
      end

      def block_method
        blocking ? :delete : :post
      end

      def block_title
        blocking ? "Unblock user" : "Block user"
      end

      def block_btn_class
        blocking ? "btn" : "btn btn-danger"
      end

      def report_abuse_path
        flavored_contact_path(flavor: "report-abuse", report: "#{user.display_login} (user)")
      end

      def block_help_url
        "#{GitHub.help_url}/articles/blocking-a-user-from-your-personal-account"
      end

      def report_help_url
        "#{GitHub.help_url}/articles/reporting-abuse-or-spam"
      end
    end
  end
end
