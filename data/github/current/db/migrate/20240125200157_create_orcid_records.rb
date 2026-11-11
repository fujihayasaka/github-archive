# typed: true
# frozen_string_literal: true

class CreateOrcidRecords < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :orcid_records, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.timestamps

      t.references :user, type: :bigint, unsigned: true, null: false, index: { unique: true }
      t.string :identifier, null: false, limit: 20, index: true
    end
  end
end
