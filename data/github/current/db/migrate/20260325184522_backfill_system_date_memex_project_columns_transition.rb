# typed: true
# frozen_string_literal: true

require "github/transitions/20260325184522_backfill_system_date_memex_project_columns"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillSystemDateMemexProjectColumnsTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillSystemDateMemexProjectColumns.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
