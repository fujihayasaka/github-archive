# typed: true
# frozen_string_literal: true

require "github/transitions/20260327214914_backfill_multipart_group_member_result_id"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillMultipartGroupMemberResultIdTransition < ActiveRecord::Migration[8.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillMultipartGroupMemberResultId.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
