# typed: true
# frozen_string_literal: true

require "github/transitions/20250414010258_backfill_ghes_pull_request_review_comment_attachments"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillGhesPullRequestReviewCommentAttachmentsTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillGhesPullRequestReviewCommentAttachments.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
