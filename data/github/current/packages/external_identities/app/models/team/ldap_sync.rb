# typed: false
# frozen_string_literal: true

module Team::LdapSync

  # Public: The job class to queue when an ldap sync is fired up.
  def sync_job_class
    LdapTeamSyncJob
  end

  # Public: Override LdapMapping::Subject#ldap_mapped? to require LDAP Sync
  # be enabled for a Team to be consider mapped to an LDAP Group.
  def ldap_mapped?
    GitHub.ldap_sync_enabled? && super
  end

  def ldap_syncing?
    ldap_mapped? && ldap_mapping.syncing?
  end

  def ldap_synced?
    ldap_mapped? && ldap_mapping.synced?
  end

  def ldap_sync_failed?
    ldap_mapped? && ldap_mapping.error?
  end

  def ldap_syncing_queued?
    ldap_mapped? && ldap_mapping.queued?
  end

  def ldap_sync_in_progress?
    ldap_syncing? || ldap_syncing_queued?
  end

  def ldap_sync_stopped?
    ldap_synced? || ldap_sync_failed?
  end

  def after_first_sync
    instrument :ldap_import, dn: ldap_dn
  end

  # Public: Add an error to the base to indicate that the ldap dn doesn't exist.
  #
  # dn: is the ldap dn that the user tried to map the team to
  #
  # Returns nothing
  def add_invalid_group_error(dn)
    errors.add :base, "LDAP group with DN #{dn} doesn't exist"
  end

  def add_non_owner_group_error
    errors.add :base, "Only organization administrators can setup LDAP mappings for a team"
  end
end
