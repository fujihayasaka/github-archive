# typed: true
# frozen_string_literal: true

class AddEmailSentToBillingPlatformEnabledProduct < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :billing_platform_enabled_products, bulk: true do |t|
      t.boolean :email_sent, null: false, default: false, comment: "Whether or not the customer has been sent an email about their planned migration to billing-platform"

      t.remove_index [:planned_migration_date, :migration_date]
      t.index [:planned_migration_date, :migration_date, :email_sent], name: "index_bpep_on_migration_dates_and_email_sent", comment: "Index for finding all customers with a planned migration date and not emailed yet"
    end
  end
end
