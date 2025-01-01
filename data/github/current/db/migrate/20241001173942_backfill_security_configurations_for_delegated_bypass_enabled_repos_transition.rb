# typed: true
# frozen_string_literal: true

require "github/transitions/20241001173942_backfill_security_configurations_for_delegated_bypass_enabled_repos"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillSecurityConfigurationsForDelegatedBypassEnabledReposTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSecurityConfigurationsForDelegatedBypassEnabledRepos.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
