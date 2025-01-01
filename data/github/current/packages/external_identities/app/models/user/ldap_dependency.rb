# typed: false
# frozen_string_literal: true

module User::LdapDependency
  extend ActiveSupport::Concern
  include LdapMapping::Subject

  # Public: The job class to queue when an ldap sync is fired up.
  def sync_job_class
    LdapUserSyncJob
  end

  class_methods do
    # Public: Find all users that map the list of ldap mappings.
    #
    # mappings: is an array with the ldap mappings to match.
    #
    # Returns an array of User.
    def find_by_ldap_mappings(*mappings)  # rubocop:disable GitHub/FindByDef
      hashed_mappings = mappings.map { |dn| LdapMapping.hash_dn(dn) }
      User.joins(:ldap_mapping).where("ldap_mappings.dn_hash in (?)",  hashed_mappings).preload(:ldap_mapping).to_a
    end
  end

  # Public: Check if a new user needs to sync her team memberships with the ldap server.
  #
  # Returns false when the instance doesn't use ldap.
  # Returns true when the attribute :needs_ldap_memberships_sync is true
  def sync_ldap_memberships?
    GitHub.ldap_sync_enabled? && ldap_mapped? && needs_ldap_memberships_sync?
  end

  # Public: Mark this user as synced.
  # So when she signs in again we don't present the sync view.
  #
  # Returns nothing.
  def ldap_memberships_synced!
    update!(needs_ldap_memberships_sync: false)
  end

  # Public: Ldap fallback uid for ldap users that change their logins.
  #
  # Returns the original user login.
  def ldap_fallback_uid
    ldap_mapping && ldap_mapping.fallback_uid
  end

  # Public: Push a job to sync the team memberhsips for a new user.
  #
  # Returns nothing
  def enqueue_new_member_sync
    LdapNewMemberSyncJob.perform_later(self.id)
  end

  # Public: Is this user's suspension being managed externally? Returns true if
  # LDAP sync is enabled, the user has an LDAP mapping, and the LDAP server is
  # ActiveDirectory (supports `userAccountControl`) attribute.
  #
  # Returns a Boolean.
  def external_account_suspension?
    return false unless GitHub.ldap_sync_enabled? && ldap_mapped?
    begin
      entry = ldap_mapping.entry
      entry && !entry[GitHub::Authentication::LDAP::ACCOUNT_CONTROL_ATTR].empty?
    rescue Net::LDAP::Error => e
      GitHub::Authentication.logger.error("LDAP error when attemptiong to suspend user", "gh.enduser.login" => login, "exception" => e)
      false
    end
  end
end
