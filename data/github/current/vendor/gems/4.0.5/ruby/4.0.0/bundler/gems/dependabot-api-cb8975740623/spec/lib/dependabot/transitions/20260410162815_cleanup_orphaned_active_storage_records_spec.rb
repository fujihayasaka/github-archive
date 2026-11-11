# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../lib/dependabot/transitions/20260410162815_cleanup_orphaned_active_storage_records.rb"

RSpec.describe Dependabot::Transitions::CleanupOrphanedActiveStorageRecords do
  let(:transition) do
    described_class.new(dry_run: false)
  end

  let(:messages) { [] }

  before do
    allow(transition).to receive(:log) { |msg| messages << msg }
  end

  context "write" do
    it "deletes orphaned attachments and their associated blobs" do
      # Create some orphaned attachments (parent record deleted)
      orphaned_attachments = [
        *create_orphaned_attachments(3, type: :pending_pull_request),
        *create_orphaned_attachments(2, type: :pending_pull_request_update),
      ]
      blob_ids = orphaned_attachments.map(&:blob_id)

      transition.perform

      # Verify all orphaned attachments were deleted
      expect(ActiveStorage::Attachment.where(id: orphaned_attachments.map(&:id)).count).to eq(0)

      # Verify associated blobs were also deleted
      expect(ActiveStorage::Blob.where(id: blob_ids).count).to eq(0)

      # Verify completion log message
      expect(messages).to include(match(/Cleanup complete. Total orphaned attachments deleted: 5/))
    end

    it "does not delete attachments that still have a parent record" do
      # Create an attachment with a valid parent record
      valid_attachment = create_valid_attachment

      # Create orphaned attachments
      orphaned_attachments = create_orphaned_attachments(2)

      transition.perform

      # Verify valid attachment was NOT deleted
      expect(ActiveStorage::Attachment.exists?(valid_attachment.id)).to be true

      # Verify orphaned attachments were deleted
      expect(ActiveStorage::Attachment.where(id: orphaned_attachments.map(&:id)).count).to eq(0)

      # Verify summary reflects only orphaned records
      expect(messages).to include(match(/Cleanup complete. Total orphaned attachments deleted: 2/))
    end

    it "processes orphaned attachments in batches" do
      # Create enough orphaned attachments to span multiple write batches
      # With BATCH_SIZE = 10, 25 attachments should produce 3 write batches
      stub_const("Dependabot::Transitions::CleanupOrphanedActiveStorageRecords::BATCH_SIZE", 10)
      orphaned_attachments = create_orphaned_attachments(25)

      transition.perform

      # Verify all orphaned attachments were deleted
      expect(ActiveStorage::Attachment.where(id: orphaned_attachments.map(&:id)).count).to eq(0)

      # Verify that multiple "Deleted" log messages were produced (one per write batch)
      delete_messages = messages.select { |m| m.start_with?("PendingPullRequest: Deleted") }
      expect(delete_messages.length).to be > 1, "Expected multiple write batches but got #{delete_messages.length}"

      # Verify final summary
      expect(messages).to include(match(/Cleanup complete. Total orphaned attachments deleted: 25/))
    end

    it "with no orphaned attachments logs zero deleted" do
      transition.perform
      expect(messages).to include(match(/Cleanup complete. Total orphaned attachments deleted: 0/))
    end
  end

  context "dry run" do
    let(:transition) { described_class.new(dry_run: true) }

    it "logs total orphaned attachments without deleting any records" do
      # Create some orphaned attachments (parent record deleted)
      orphaned_attachments = create_orphaned_attachments(5)

      transition.perform

      # Verify no records were deleted
      expect(ActiveStorage::Attachment.where(id: orphaned_attachments.map(&:id)).count).to eq(5)

      # Verify dry run log messages
      expect(messages).to include(match(/PendingPullRequest: Found/))
      expect(messages).to include(match(/DRY RUN complete. Total orphaned attachments found: 5/))

      # Verify no delete messages were logged
      expect(messages).not_to include(match(/Deleted/))
    end

    it "with no orphaned attachments logs zero total" do
      transition.perform
      expect(messages).to include(match(/DRY RUN complete. Total orphaned attachments found: 0/))
    end
  end

  private

  # Creates orphaned ActiveStorage::Attachment records by creating attachments
  # and then deleting their parent record, leaving the attachments dangling.
  def create_orphaned_attachments(count, type: :pending_pull_request)
    create_list(type, count).map do |record|
      record.message_data = { "commit_message" => "Bump business from 1.3.0 to 1.4.0" }
      attachment = record.reload.encrypted_message_data_blob_attachment
      record.delete # Delete parent without callbacks to leave attachment orphaned
      attachment
    end
  end

  # Creates a valid ActiveStorage::Attachment with an intact parent record.
  def create_valid_attachment
    record = create(:pending_pull_request)
    record.message_data = { "commit_message" => "Bump business from 1.3.0 to 1.4.0" }
    record.reload.encrypted_message_data_blob_attachment
  end
end
