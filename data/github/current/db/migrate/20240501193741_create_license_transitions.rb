class CreateLicenseTransitions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    create_table :licensing_model_transitions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :customer_id, unsigned: true, null: false, index: true, comment: "The customer this transition is for"
      t.date :transition_date, null: false, comment: "The date of the transition"
      t.integer :status, null: false, default: 0, comment: "The status of the transition"
      t.integer :licensing_model, null: false, comment: "The updated licensing model to apply"

      t.index [:transition_date, :customer_id], unique: true, name: :index_licensing_transitions_on_transition_date_and_customer_id
      t.timestamps
    end
  end
end
