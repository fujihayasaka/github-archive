# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class ImpersonationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include StafftoolsHelper

      attr_reader :user

      def active_grant
        @active_grant ||= user.active_staff_access_grant
      end

      def active_request
        @active_request ||= user.active_staff_access_request
      end

      def message
        case status
        when :missing_impersonation_privileges
          stafftools_not_authorized_html
        when :self_impersonation
          "Wait a minute… you can’t use this section on your own account!"
        when :site_admin_or_employee
          "Sorry, you can’t impersonate a site administrator’s account."
        when :suspended_user
          "Sorry, you can’t impersonate a suspended user’s account."
        when :access_request_pending
          "Permission to impersonate @#{user} has already been requested. \
          The current access request will automatically expire on #{current_request_expires_at}"
        when :access_grant_required
          "You must request permission from the user before you can impersonate them."
        end
      end

      def status
        @status ||=
          case
          when !current_user.can_fake_login?
            :missing_impersonation_privileges
          when self_impersonation?
            :self_impersonation
          when user.site_admin? || user.employee?
            :site_admin_or_employee
          when user.suspended?
            :suspended_user
          when active_request
            :access_request_pending
          when user_missing_staff_access_grant?
            :access_grant_required
          else
            :allowed
          end
      end

      def show_override_option?
        current_user.can_impersonate_users_without_permission? && user_can_be_impersonated?
      end

      def log_placeholder
        "Include a link/reason to be logged with this request."
      end

      def impersonation_reasons
        [
          "I am troubleshooting a problem for the user",
          "The user is not available to act, and is blocking other users from being productive",
          "The user requested that I take an action on their behalf",
          "Other"
        ]
      end

      private

      def user_can_be_impersonated?
        ![:self_impersonation,
          :suspended_user,
          :site_admin_or_employee].include?(status)
      end

      def user_missing_staff_access_grant?
        current_user.access_grant_required_for_user_impersonation? && !active_grant
      end

      def self_impersonation?
        user == current_user
      end

      def current_request_expires_at
        active_request&.expires_at.strftime("%m/%d/%Y at %H:%M %Z")
      end
    end
  end
end
