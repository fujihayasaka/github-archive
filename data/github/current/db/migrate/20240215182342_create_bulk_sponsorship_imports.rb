# typed: true
# frozen_string_literal: true

class CreateBulkSponsorshipImports < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    create_table(:bulk_sponsorship_imports, id: :bigint, unsigned: true, charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci",
    ) do |t|
      t.bigint :sponsor_id, null: false, unsigned: true
      t.json :data, null: false
      t.timestamps null: false

      t.index :sponsor_id, unique: true
    end
  end
end
