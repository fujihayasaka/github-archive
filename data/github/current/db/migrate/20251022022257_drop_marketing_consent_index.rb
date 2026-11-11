# typed: true

class DropMarketingConsentIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SignupFlow)

  def change
    remove_index :user_marketing_consents, :marketing_consent, if_exists: true
  end
end
