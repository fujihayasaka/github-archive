# typed: true
# frozen_string_literal: true

require "github/transitions/20260127134856_backfill_business_team_org_assignments_business_id"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillBusinessTeamOrgAssignmentsBusinessIdTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillBusinessTeamOrgAssignmentsBusinessId.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
