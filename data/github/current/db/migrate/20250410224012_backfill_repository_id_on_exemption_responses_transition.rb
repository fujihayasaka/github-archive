# typed: true
# frozen_string_literal: true

require "github/transitions/20250410224012_backfill_repository_id_on_exemption_responses"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillRepositoryIdOnExemptionResponsesTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillRepositoryIdOnExemptionResponses.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
