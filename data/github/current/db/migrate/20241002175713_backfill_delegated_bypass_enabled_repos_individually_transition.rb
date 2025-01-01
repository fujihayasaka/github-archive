# typed: true
# frozen_string_literal: true

require "github/transitions/20241002175713_backfill_delegated_bypass_enabled_repos_individually"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillDelegatedBypassEnabledReposIndividuallyTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillDelegatedBypassEnabledReposIndividually.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
