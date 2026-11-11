# typed: true


class AddCompositeIndexUserMarketingConsents < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SignupFlow)

  def change
    add_index :user_marketing_consents, [:marketing_consent, :created_at, :onboarding_optout_date], name: "index_umc_on_marketing_consent_created_at_optout_date"
  end
end
