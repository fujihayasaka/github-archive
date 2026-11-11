# typed: true
# frozen_string_literal: true

class CreateBusinessIntents < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Accounts)

  def change
    create_table :business_intents, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :business_id, unsigned: true, null: false
      t.column :intent, :tinyint, unsigned: true, null: false

      t.timestamps

      t.index [:business_id, :intent], unique: true, name: "idx_business_intent"
    end
  end
end
