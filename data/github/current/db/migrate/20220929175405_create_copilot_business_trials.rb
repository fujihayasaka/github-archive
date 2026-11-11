# typed: true

class CreateCopilotBusinessTrials < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_business_trials, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :trialable, polymorphic: true, type: "BIGINT(20) UNSIGNED", null: false, index: { unique: true }, comment: "The object (Business/Enterprise or Org) that this trial is for"
      t.integer    :seat_count, null: false, comment: "The number of seats in the trial"
      t.datetime   :ends_at, precision: 6, null: false, comment: "The time the trial ends"
      t.references :managing_user, index: { unique: false }, null: false
      t.timestamps
    end
  end
end
