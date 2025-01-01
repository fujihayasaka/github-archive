# typed: true
# frozen_string_literal: true

class LdapNewMemberSyncJob < ApplicationJob
  queue_as :ldap_new_member_sync

  class MissingMappingError < StandardError
    def initialize(user)
      @user = user
    end

    def message
      "LDAP mapping not found for user #{@user.id}: #{@user.login}"
    end

    def payload
      { user: @user }
    end
  end

  # Public: Sync LDAP attributes for user by the given `user_id`
  #
  # Emits `ldap_new_member_sync.perform` event with:
  #  :login - login of the user being synced
  def perform(user_id)
    return unless GitHub.enterprise? && GitHub.ldap_sync_enabled?

    user = User.includes(:ldap_mapping).find(user_id)

    GitHub.instrument "ldap_new_member_sync.perform" do |_payload|
      if user.ldap_mapping.present?
        with_write { GitHub::LDAP::NewMemberSync.new.perform(user) }
      else
        error = MissingMappingError.new(user)
        Failbot.report! error, error.payload
      end
    end
  end
end
