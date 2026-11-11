# typed: true
# frozen_string_literal: true

require "github/transitions/20241002185303_backfill_security_configs_for_delegated_bypass_disabled_orgs"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillSecurityConfigsForDelegatedBypassDisabledOrgsTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSecurityConfigsForDelegatedBypassDisabledOrgs.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
