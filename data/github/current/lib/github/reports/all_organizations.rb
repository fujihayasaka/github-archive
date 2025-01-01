# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    class AllOrganizations
      def data
        header   = %w(id created_at login email admins members teams repos 2fa_required?)

        if GitHub.enterprise?
          conditions = [
            "id != ?
              AND type = 'Organization'",
            GitHub.trusted_apps_owner_id,
          ]
        else
          conditions = [
            "type = 'Organization'",
          ]
        end

        CSV.generate do |csv|
          csv << header
          Organization.where(conditions).find_each do |o|
            csv << [o.id, o.created_at, o.login, o.billing_email, o.admins.count,
                    o.member_count, o.teams.count, o.org_repositories.count, o.two_factor_requirement_enabled?]
          end
        end
      end
    end
  end
end
