# typed: true
# given a billing cycle end date, we want to know:
# 1. how many seats were carried over from previous billing cycle
# 2. how many seats were added in the current billing cycle
# 3. how many seats were removed in the current billing cycle
#
# so, when a seat is created, we insert a record here. when a seat is deleted, we update the record here.

class CreateCopilotSeatHistory < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_seat_histories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # we need to reference the business that this is under for fast lookups
      # additionally, organizations can be removed from businesses and this lookup is needed to
      # accurately calculate the seat history for a business
      t.references :business, index: { unique: false }, null: false

      # we need to reference the organization that this is under for fast lookups
      t.references :organization, index: { unique: false }, null: false

      # this can be deleted but it's cool to have the id at least
      t.references :seat, index: { unique: true }, null: true

      # this can be deleted too but it's cool to have the id at least
      t.references :assigned_user, index: { unique: false }, null: true

      # we need to know when this seat was created and started billing
      t.date :seat_created_at, null: true

      # when the seat assignment was deleted and the seat stopped billing
      t.date :seat_deleted_at, null: true

      # given that these can change, we need to store the values at the time of the billing cycle
      t.date :billing_cycle_start_date, null: false

      # given that these can change, we need to store the values at the time of the billing cycle
      t.date :billing_cycle_end_date, null: false

      t.timestamps
    end
  end
end
