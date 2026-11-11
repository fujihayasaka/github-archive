# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :title

      def show_staffnote?
        suspended?
      end

      def show_public_key_audit?
        GitHub.ssh_audit_enabled? && all_users?
      end

      def staffnote(user)
        github_id = ::User.where(login: :github).pluck(:id).first
        conditions = github_id ? ["user_id <> ?", github_id] : []
        user.staff_notes.where(conditions).last
      end

      private

      def all_users?
        title == "All users"
      end

      def by_ip?
        title =~ /Users at/
      end

      def site_admin?
        title == "Site admins"
      end

      def suspended?
        title == "Suspended users"
      end

    end
  end
end
