# typed: true

class UserSignups < ActiveRecord::Migration[8.1]

  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :user_signups, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user, null: false, index: true, type: :bigint, unsigned: true
      t.string :email, limit: 255, null: false, comment: "email address used to sign up"
      t.string :country_code, limit: 2, null: false, comment: "2 character country code of the user"
      t.integer :marketing_consent, null: true, index: { unique: false }, comment: "consent to receive marketing emails"
      t.datetime :onboarding_optout_date, null: true, index: { unique: false }, precision: 6, comment: "date the user opted out of onboarding emails"
      t.timestamps precision: 6
    end
  end
end
