# typed: true
# frozen_string_literal: true

class AddDrainTrackingAndSkipPreflightColumnsToElmExporterMigrations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    change_table :elm_exporter_migrations, bulk: true do |t|
      t.datetime :backfill_delivered_at, precision: 6, null: true
      t.datetime :events_delivered_at, precision: 6, null: true
      t.boolean :skip_preflight, null: false, default: false
    end
  end
end
