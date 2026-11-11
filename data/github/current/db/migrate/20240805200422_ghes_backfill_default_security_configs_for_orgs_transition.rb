# rubocop:disable GitHub/ConnectionClassPresentInMigration
# typed: true
# frozen_string_literal: true

require "github/transitions/20240805200422_ghes_backfill_default_security_configs_for_orgs"

class GhesBackfillDefaultSecurityConfigsForOrgsTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::GhesBackfillDefaultSecurityConfigsForOrgs.new(arguments)
    transition.run
  end

  def self.down
  end
end
