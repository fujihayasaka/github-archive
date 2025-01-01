# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class TeamSyncView < Stafftools::LdapSyncView
      attr_reader :user

      def sync_path
        sync_stafftools_user_team_ldap_path(user, subject.to_param)
      end

      def change_ldap_dn_path
        stafftools_user_team_ldap_path(user, subject.to_param)
      end

      def audit_log_path
        query =
          if GitHub.driftwood_ade_queries_enabled?
            <<~KQL
              webevents
              | where org_id == #{subject.organization_id}
                  and action startswith "team.ldap_sync"
            KQL
          else
            "org_id:#{subject.organization_id} action:team.ldap_sync*"
          end

        stafftools_audit_log_path(query: query)
      end

      def subject_label
        subject.name
      end

      def ldap_map_label
        "LDAP Group"
      end
    end
  end
end
