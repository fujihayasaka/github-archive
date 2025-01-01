# typed: strict
# frozen_string_literal: true

class CreateGhasUnbundleTransitions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)

  sig { void }
  def change
    create_table :ghas_unbundle_transitions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :customer_id, unsigned: true, null: false, index: true, comment: "The ID of the customer this transition is for"
      t.date :transition_date, null: false, comment: "The date of the transition"
      t.integer :status, null: false, default: 0, comment: "The status of the transition"
      t.integer :target_sku_state, null: false, default: 0, comment: "The target SKU state to transition to, unbundled (0) or bundled (1)"
      t.bigint :actor_id, unsigned: true
      t.string :message

      t.index [:transition_date, :customer_id], unique: true, name: :index_ghas_unbundling_transitions_on_date_and_customer_id

      t.timestamps
    end
  end
end
