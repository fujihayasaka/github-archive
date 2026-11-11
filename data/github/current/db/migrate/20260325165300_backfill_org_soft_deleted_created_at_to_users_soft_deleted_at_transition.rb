# typed: true
# frozen_string_literal: true

require "github/transitions/20260325165300_backfill_org_soft_deleted_created_at_to_users_soft_deleted_at"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillOrgSoftDeletedCreatedAtToUsersSoftDeletedAtTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillOrgSoftDeletedCreatedAtToUsersSoftDeletedAt.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
