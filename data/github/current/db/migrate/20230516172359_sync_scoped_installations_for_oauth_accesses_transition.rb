# frozen_string_literal: true

require "github/transitions/20230516172359_sync_scoped_installations_for_oauth_accesses"

class SyncScopedInstallationsForOauthAccessesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::SyncScopedInstallationsForOauthAccesses.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
