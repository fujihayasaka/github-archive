# typed: true
# frozen_string_literal: true

# Creates the `security_configuration_bulk_attachments` table for the
# Attachment Pipeline (Milestone 1).
#
# One row per bulk attachment request. Captures the customer's intent to
# attach a configuration to a set of repositories and tracks staging progress
# via a cursor.
#
# See:
# - https://github.com/github/security-products-enablement/issues/2788
# - https://github.com/github/security-products-enablement/blob/main/docs/adrs/2026-03-18-security-configuration-attachment-pipeline.md
class CreateSecurityConfigurationBulkAttachments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::SecurityProductsEnablement)

  def change
    create_table :security_configuration_bulk_attachments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :parent_id, unsigned: true
      t.bigint :security_configuration_id, null: false, unsigned: true
      t.integer :security_configuration_version, null: false, unsigned: true
      t.bigint :business_id, unsigned: true
      t.bigint :owner_id, null: false, unsigned: true
      t.bigint :actor_id, null: false, unsigned: true
      t.json :repository_selection, null: false
      t.json :attachment_options, null: false
      t.integer :state, null: false, limit: 1, unsigned: true, default: 0
      t.string :state_reason, limit: 255
      t.string :staging_cursor, limit: 255
      t.integer :staging_attempt, null: false, unsigned: true, default: 0
      t.json :attachment_progress, null: false
      t.timestamps

      t.index [:state, :updated_at], name: "index_bulk_attachments_on_state_and_updated_at"
      t.index [:parent_id, :state], name: "index_bulk_attachments_on_parent_id_and_state"
      t.index [:security_configuration_id], name: "index_bulk_attachments_on_security_configuration_id"
      t.index [:business_id], name: "index_bulk_attachments_on_business_id"
      t.index [:owner_id], name: "index_bulk_attachments_on_owner_id"
    end
  end
end
