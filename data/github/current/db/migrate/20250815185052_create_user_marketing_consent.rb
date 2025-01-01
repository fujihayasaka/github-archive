# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex

class CreateUserMarketingConsent < ActiveRecord::Migration[8.1]

  self.use_connection_class(ApplicationRecord::Domain::SignupFlow)

  def change
    create_table :user_marketing_consents, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, null: false, unsigned: true
      t.string :email, limit: 255, null: false, comment: "email address used to sign up"
      t.string :country_code, limit: 2, null: false, comment: "2 character country code of the user"
      t.integer :marketing_consent, null: true, index: { unique: false }, comment: "consent to receive marketing emails"
      t.datetime :onboarding_optout_date, null: true, index: { unique: false }, precision: 6, comment: "date the user opted out of onboarding emails"
      t.timestamps precision: 6
      t.index :email, name: "index_user_marketing_consents_on_email"
      t.index :created_at, name: "index_user_marketing_consents_on_created_at"
      t.index :updated_at, name: "index_user_marketing_consents_on_updated_at"
    end
  end
end
