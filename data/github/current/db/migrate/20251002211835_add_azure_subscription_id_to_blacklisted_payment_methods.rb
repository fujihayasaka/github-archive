# rubocop:disable Naming/InclusiveLanguage
# typed: strict

class AddAzureSubscriptionIdToBlacklistedPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def change
    add_column :blacklisted_payment_methods, :azure_subscription_id, :string, limit: 36, null: true # rubocop:disable Naming/InclusiveLanguage
  end
end
# rubocop:enable Naming/InclusiveLanguage
