# typed: true
# frozen_string_literal: true

module Stafftools
  class LdapSyncView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers

    attr_reader :subject

    def show_ldap?
      return false unless GitHub.auth.ldap?
      return false unless user? || team?
      !!ldap_map
    end

    def show_ldap_sync?
      show_ldap? && GitHub.ldap_sync_enabled?
    end

    def ldap_map
      @ldap_map ||= subject.ldap_mapping
    end

    def synced?
      ldap_map.synced?
    end

    def sync_status_label
      case ldap_map.sync_status
      when "synced"            then "Synced."
      when "error"             then "Error syncing."
      when "syncing", "queued" then "Syncing…"
      when "gone"              then "Error: LDAP entry missing."
      else                          "Not synced yet."
      end
    end

    def last_sync_duration
      ldap_map.last_sync_ms.round(2)
    end

    def last_sync_at
      ldap_map.last_sync_at
    end

    def user?
      subject.try(:user?)
    end

    def team?
      subject.is_a?(::Team)
    end

    def organization?
      subject.try(:organization?)
    end
  end
end
