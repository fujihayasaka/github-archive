# typed: true
# frozen_string_literal: true

# Creates the `security_configuration_attachments` table for the
# Attachment Pipeline (Milestone 1).
#
# One row per repository per attachment operation. Each row is a
# self-contained work item containing everything an attacher needs to
# perform the work without joining back to any parent record. Provides
# durable, per-repo attachment history that doesn't exist today (currently
# tracked ephemerally in Redis via `JobProgressTracker`).
#
# See:
# - https://github.com/github/security-products-enablement/issues/2790
# - https://github.com/github/security-products-enablement/blob/main/docs/adrs/2026-03-18-security-configuration-attachment-pipeline.md
class CreateSecurityConfigurationAttachments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    create_table :security_configuration_attachments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :bulk_attachment_id, unsigned: true
      t.bigint :security_configuration_id, null: false, unsigned: true
      t.integer :security_configuration_version, null: false, unsigned: true
      t.bigint :business_id, unsigned: true
      t.bigint :owner_id, null: false, unsigned: true
      t.bigint :actor_id, null: false, unsigned: true
      t.bigint :repository_id, null: false, unsigned: true
      t.json :attachment_options, null: false
      t.integer :state, null: false, limit: 1, unsigned: true, default: 0
      t.string :state_reason, limit: 255
      t.timestamps

      t.index [:bulk_attachment_id, :state], name: "index_attachments_on_bulk_attachment_id_and_state"
      t.index [:state, :updated_at], name: "index_attachments_on_state_and_updated_at"
      t.index [:security_configuration_id], name: "index_attachments_on_security_configuration_id"
      t.index [:business_id], name: "index_attachments_on_business_id"
      t.index [:owner_id], name: "index_attachments_on_owner_id"
      t.index [:repository_id], name: "index_attachments_on_repository_id"
    end
  end
end
