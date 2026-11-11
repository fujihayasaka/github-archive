# typed: true

class UpdateMarketingConsentCompositeIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SignupFlow)

  def up
    change_table :user_marketing_consents, bulk: true do |t|
      t.remove_index name: "index_umc_on_marketing_consent_created_at_optout_date"
      t.index [:marketing_consent, :onboarding_optout_date, :created_at], name: "index_umc_on_mc_and_optout_and_created"
    end
  end

  def down
    change_table :user_marketing_consents, bulk: true do |t|
      t.index [:marketing_consent, :onboarding_optout_date, :created_at], name: "index_umc_on_marketing_consent_created_at_optout_date"
      t.remove_index name: "index_umc_on_mc_and_optout_and_created"
    end
  end
end
