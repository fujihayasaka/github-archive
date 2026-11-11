# typed: true
# frozen_string_literal: true

require "github/transitions/20241018211615_backfill_ghes_pats_exp_configuration"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillGhesPatsExpConfigurationTransition < ActiveRecord::Migration[8.0]
  def self.up
    return if !GitHub.enterprise?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillGhesPatsExpConfiguration.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
