# typed: true
# frozen_string_literal: true

class Team
  class LdapEditor < Editor
    def update(attributes, group_mappings: [])
      ldap_dn = attributes.delete(:ldap_dn)

      # Ajax updates don't send the ldap_dn
      # We ignore the group management to not remove the ldap mapping by mistake.
      return super if ldap_dn.nil?

      if ldap_dn.present?
        # Ignore LDAP DN if it's unchanged
        return super if @team.ldap_mapped? && @team.ldap_dn == ldap_dn

        if @team.legacy_owners?
          @team.errors.add :base, "Owners team cannot be mapped to an LDAP Group"
          return false
        end

        # If the org is not adminable by the person making the request
        # add the error statement and bail out before making an LDAP call
        #
        # They can still update other aspects but just not any LDAP mappings
        if !@team.organization.adminable_by?(@updater)
          if !@updater.site_admin?
            @team.add_non_owner_group_error
            return false
          end
        end

        group = GitHub::LDAP.search.find_group(ldap_dn)

        if group
          updated = super && @team.map_ldap_entry(group.dn)
          @team.enqueue_sync_job if updated
        else
          @team.add_invalid_group_error(ldap_dn)
        end
      else
        if updated = super
          updated = @team.ldap_mapping.destroy if @team.ldap_mapped?
        end

        @team.reload if updated # clear cached association
      end

      updated
    end
  end
end
