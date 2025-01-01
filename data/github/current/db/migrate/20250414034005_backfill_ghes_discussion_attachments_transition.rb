# typed: true
# frozen_string_literal: true

require "github/transitions/20250414034005_backfill_ghes_discussion_attachments"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillGhesDiscussionAttachmentsTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillGhesDiscussionAttachments.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
