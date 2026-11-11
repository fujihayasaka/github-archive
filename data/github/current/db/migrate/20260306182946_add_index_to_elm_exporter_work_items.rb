# typed: true
# frozen_string_literal: true

class AddIndexToElmExporterWorkItems < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    change_table :elm_exporter_work_items, bulk: true do |t|
      t.index [:component, :status, :lease_expires_at], name: "idx_elm_exporter_work_items_claimability"
      t.index [:migration_id, :component, :status], name: "idx_elm_exporter_work_items_migration_id_component_status"
      t.index [:status], name: "idx_elm_exporter_work_items_status"
    end
  end
end
