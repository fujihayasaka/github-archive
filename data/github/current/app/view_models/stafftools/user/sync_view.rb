# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class SyncView < Stafftools::LdapSyncView
      include AuditLogHelper

      def sync_path
        sync_stafftools_user_ldap_path(subject)
      end

      def change_ldap_dn_path
        stafftools_user_ldap_path(subject)
      end

      def audit_log_path
        query =
          if driftwood_ade_query?(current_user)
            <<~KQL
              webevents
              | where user_id == #{subject.id}
                  and action startswith "user.ldap_sync"
            KQL
          else
            "user_id:#{subject.id} action:user.ldap_sync*"
          end

        stafftools_audit_log_path(query: query)
      end

      def subject_label
        subject.login
      end

      def ldap_map_label
        "LDAP Entity"
      end
    end
  end
end
