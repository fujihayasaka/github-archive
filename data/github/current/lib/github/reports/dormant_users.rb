# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    # This report is only used in GHES. It's registered as one of the
    # available report types in `lib/github/reports.rb`
    # https://github.com/github/github/blob/9bb6fda1d6d3fcb52b3cd8e2f2ea3bb653d2806a/lib/github/reports.rb#L21
    class DormantUsers
      def data(threshold: GitHub.dormancy_threshold, no_dormancy_exemptions: false)
        users = User.dormant_users(threshold: threshold, no_dormancy_exemptions: no_dormancy_exemptions)

        CSV.generate do |csv|
          csv << header
          users.each do |u|
            csv << rows(u)
          end
        end
      end

      private

      def header
        %w(created_at id login email role suspended?
          last_logged_ip repos ssh_keys org_memberships
          dormant? last_active raw_login 2fa_enabled?
          ssh_keys_last_access pats pats_last_access)
      end

      def rows(u)
        [u.created_at, u.id, u.login, u.email, (u.site_admin? ? "admin" : "user"),
          u.suspended?, u.last_ip, u.repositories.count, u.public_keys.count,
          u.organizations.count, u.dormant?, u.last_active, u.raw_login, u.two_factor_authentication_enabled?,
          u.last_public_key_access_time, u.oauth_accesses.personal_tokens.size, u.last_personal_token_access_time]
      end
    end

    # This version of the report is only run on GHEC and is invoked from
    # the GHECAdmin::EnterpriseDormantUsersExport as part of the
    # ProcessDormantUsersExportJob background job
    class GHECDormantUsers
      extend T::Sig

      class Row < T::Struct
        const :user, User
        const :outside_collaborator, T::Boolean
      end

      def data(threshold: GitHub.dormancy_threshold, business_id:, business_report_export:)
        GitHub.logger.info("Getting dormant users for business", "gh.business.id" => business_id)
        ghec_data(threshold:, business_id:, business_report_export:)
      end

      private

      def ghec_data(threshold:, business_id:, business_report_export:)
        results = User.dormant_users_for_business(threshold: threshold, business_id: business_id, business_report_export: business_report_export)

        rows = []
        results.members.each do |u|
          rows << Row.new(user: u, outside_collaborator: false)
        end

        results.outside_collaborators.each do |u|
          rows << Row.new(user: u, outside_collaborator: true)
        end

        CSV.generate do |csv|
          csv << header
          rows.each do |u|
            csv << row(u)
          end
        end
      end

      def header
        %w(created_at id login role last_logged_ip 2fa_enabled? outside_collaborator)
      end

      sig { params(row_object: Row).returns(T::Array[String]) }
      def row(row_object)
        u = row_object.user

        base_columns = [u.created_at, u.id, u.login, (u.site_admin? ? "admin" : "user"), u.last_ip, u.two_factor_authentication_enabled?]
        base_columns << row_object.outside_collaborator
        base_columns
      end
    end
  end
end
