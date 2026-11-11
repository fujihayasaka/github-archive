# typed: true
# frozen_string_literal: true

class CreateAuditLogMicrosoftPurviewSinkConfiguration < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    create_table :audit_log_microsoft_purview_sink_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/NoNewTablesOnSharedDbClusters
      t.column :tenant_id, "binary(16)", null: false
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
    end
  end
end
