# typed: true
# frozen_string_literal: true

class ChangeEmailSentToEmailSentAt < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :billing_platform_enabled_products, bulk: true do |t|
      t.remove_index [:planned_migration_date, :migration_date, :email_sent], name: "index_bpep_on_migration_dates_and_email_sent", comment: "Index for finding all customers with a planned migration date and not emailed yet"
      t.remove :email_sent

      t.datetime :email_sent_at, precision: 6, null: true, comment: "When the customer was sent an email about their planned migration to billing-platform"

      t.index [:planned_migration_date, :migration_date, :email_sent_at], name: "index_on_planned_date_migration_date_and_email_sent_at", comment: "Index for finding all customers with a planned migration date, not migrated and not emailed yet"
    end
  end

  def down
    change_table :billing_platform_enabled_products, bulk: true do |t|
      t.remove_index [:planned_migration_date, :migration_date, :email_sent_at], name: "index_on_planned_date_migration_date_and_email_sent_at", comment: "Index for finding all customers with a planned migration date, not migrated and not emailed yet"
      t.remove :email_sent_at

      t.boolean :email_sent, null: false, default: false, comment: "Whether or not the customer has been sent an email about their planned migration to billing-platform"

      t.index [:planned_migration_date, :migration_date, :email_sent], name: "index_bpep_on_migration_dates_and_email_sent", comment: "Index for finding all customers with a planned migration date and not emailed yet"
    end
  end
end
