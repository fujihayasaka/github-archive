# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddStripeCustomerIdToOrganizationProfiles < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    add_column :organization_profiles, :stripe_customer_id, :string,
      null: true, after: :sponsoring_linked_organization_id, limit: 100
  end
end
