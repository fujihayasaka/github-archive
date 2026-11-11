# typed: true
# frozen_string_literal: true

# NOTE: This migration (20260114204326) intentionally reuses the earlier
# transition 20260108211106_backfill_version_repository_metadata_permission.
# The differing timestamps are expected and do not indicate a mismatch.
require "github/transitions/20260108211106_backfill_version_repository_metadata_permission"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillVersionRepositoryMetadataPermission < ActiveRecord::Migration[8.2]
  def up
    return if !GitHub.enterprise? && !Rails.env.development?

    args = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillVersionRepositoryMetadataPermission.new(args)
    transition.run
  end

  def down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
