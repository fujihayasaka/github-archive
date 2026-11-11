# typed: true

class AddApplicationFieldsToBusinessStartupsPrograms < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :business_startups_programs, bulk: true do |t|
      t.column :application_status, "tinyint unsigned"
      t.datetime :submitted_at, precision: 6
      t.datetime :processed_at, precision: 6
      t.datetime :accepted_at, precision: 6
      t.datetime :rejected_at, precision: 6
      t.column :rejection_reason, "varchar(255)"
      t.column :payment_card_fingerprint, "varchar(255)", comment: "payment_methods.card_fingerprint which is paypal or cc."
      t.column :payment_azure_subscription_id, "varchar(255)", comment: "azure subscription id"
      t.json :application_data, comment: "zeroed out after accepted/rejected"
    end
  end
end
