# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    class AllUsers
      def data
        header = %w(created_at id login email role suspended?
                      last_logged_ip repos ssh_keys org_memberships
                      dormant? last_active raw_login 2fa_enabled?)

        conditions = [
          "login != ?
            AND type = 'User'",
          GitHub.ghost_user_login,
        ]

        CSV.generate do |csv|
          csv << header
          User.where(conditions).find_each do |u|
            csv << [u.created_at, u.id, u.login, u.email, (u.site_admin? ? "admin" : "user"),
                    u.suspended?, u.last_ip, u.repositories.count, u.public_keys.count,
                    u.organizations.count, u.dormant?, u.last_active, u.raw_login, u.two_factor_authentication_enabled?]
          end
        end
      end
    end
  end
end
