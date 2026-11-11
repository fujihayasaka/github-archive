# typed: false
# frozen_string_literal: true

class LdapMapping
  module Subject
    extend ActiveSupport::Concern

    included do
      has_one :ldap_mapping, as: :subject, dependent: :destroy
    end

    # Public: Check if a model is mapped with an ldap entry.
    #
    # Returns false if the ldap sync feature is not enabled.
    # Returns true if this subject is mapped with an ldap entry.
    def ldap_mapped?
      GitHub.auth.ldap? && ldap_mapping.present?
    end

    # Public - Create a mapping between the subject and the ldap entry keeping record of the ldap dn.
    # Update the ldap mapping when it exists.
    #
    # user: is the logged in User.
    # entry_dn: is the entry dn information from ldap.
    #
    # Returns true if the mapping could be saved.
    def map_ldap_entry(entry_dn)
      ActiveRecord::Base.connected_to(role: :writing) do
        if ldap_mapping
          ldap_mapping.update(dn: entry_dn)
        else
          create_ldap_mapping(dn: entry_dn)
        end
      end
    end

    # Public - Add a sync job to the queue.
    # It modifies the sync status to :queued.
    #
    # Returns nothing.
    def enqueue_sync_job
      return unless ldap_mapped?

      ldap_mapping.update(sync_status: :queued)
      sync_job_class.perform_later(self.id)
    end

    # Internal: First sync event callback. Overridable.
    #
    # Returns nothing.
    def after_first_sync
    end

    # Public - String representation of the ldap mapping.
    # Used by the api.
    #
    # Returns the ldap mapping dn.
    def ldap_dn
      ldap_mapping && ldap_mapping.dn
    end
  end
end
