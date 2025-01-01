# typed: true
# frozen_string_literal: true

class CreateEducationDeveloperPackApplicationMetadata < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Users

  def change
    create_table(
      :education_developer_pack_application_metadata,
      id: :bigint,
      unsigned: true,
      charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci",
    ) do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :external_discount_request_id, unsigned: true, null: true
      t.integer :application_type, limit: 1, unsigned: false, null: false

      t.timestamps

      t.datetime :applied_at, null: false, precision: 6

      t.datetime :denied_at, null: true, precision: 6
      t.datetime :approved_at, null: true, precision: 6
      t.datetime :expires_at, null: true, precision: 6

      t.index :user_id
    end
  end
end
