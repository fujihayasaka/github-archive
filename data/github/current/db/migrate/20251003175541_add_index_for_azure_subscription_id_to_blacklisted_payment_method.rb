# rubocop:disable Naming/InclusiveLanguage
# typed: strict

class AddIndexForAzureSubscriptionIdToBlacklistedPaymentMethod < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def change
    add_index :blacklisted_payment_methods, [:azure_subscription_id, :owner_id, :owner_type], name: "index_blacklisted_payment_methods_on_azure_sub_id_and_owner"
  end
end

# rubocop:enable Naming/InclusiveLanguage
