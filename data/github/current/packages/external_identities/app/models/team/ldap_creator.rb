# typed: true
# frozen_string_literal: true

class Team
  class LdapCreator < Creator
    def create(attrs, maintainers:, group_mappings:)
      super do |team|
        if (ldap_dn = attrs[:ldap_dn]).present?
          if @org.resources.organization_administration.writable_by?(@creator)
            if group = ldap_group(ldap_dn)
              team.build_ldap_mapping(dn: group.dn)

              team.name       = default_name(group)       unless team.name?
              team.permission = default_permission(group) unless team.permission?
            else
              team.add_invalid_group_error(ldap_dn)
            end
          else
            team.add_non_owner_group_error
          end
        end
      end
    end

    # Skip adding the creator as a member.
    # After creating the ldap mapping a callback is fired to sync the ldap members.
    def add_initial_members(team, members)
      if team.ldap_mapped?
        team.enqueue_sync_job
      else
        super
      end
    end

    # Private - Search for the ldap group associated with a new team.
    #
    # dn: is the dn for the group entry.
    #
    # Returns nil if the authentication doesn't use ldap or there is no group.
    # Returns a Net::LDAP::Entry for the group if it exists.
    def ldap_group(dn)
      if dn.present?
        GitHub::LDAP.search.find_group(dn)
      end
    end

    # Internal: Returns the default Team name String if one is not specified
    # based on the LDAP Group's name (CN), failing back to the UID.
    def default_name(group)
      GitHub.auth.profile_info(group, :name).first
    end

    # Internal: Returns the default Team permission String if one is not
    # specified. In this case, we opt for the least permissive option.
    def default_permission(group)
      "pull"
    end
  end
end
