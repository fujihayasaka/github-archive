# typed: true
# frozen_string_literal: true

class CreatePotentialSponsorships < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    create_table :potential_sponsorships, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :potential_sponsor_id, null: false, unsigned: true
      t.bigint :potential_sponsorable_id, null: false, unsigned: true
      t.integer :state, null: false, default: 0
      t.bigint :created_by_id, null: false, unsigned: true
      t.blob :message
      t.timestamps null: false

      t.index [:potential_sponsorable_id, :potential_sponsor_id], unique: true,
        name: "index_potential_sponsorships_on_poten_sponsorable_poten_sponsor"
      t.index [:state, :potential_sponsorable_id],
        name: "idx_potential_sponsorships_on_state_and_potential_sponsorable_id"
      t.index :potential_sponsor_id
      t.index :created_by_id
    end
  end
end
