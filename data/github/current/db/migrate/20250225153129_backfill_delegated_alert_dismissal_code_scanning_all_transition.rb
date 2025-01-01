# typed: true
# frozen_string_literal: true

require "github/transitions/20250225153129_backfill_delegated_alert_dismissal_code_scanning_all"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillDelegatedAlertDismissalCodeScanningAllTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillDelegatedAlertDismissalCodeScanningAll.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
