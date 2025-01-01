# typed: true
# frozen_string_literal: true

class AddSessionLengthToOrganizationSamlProviders < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :organization_saml_providers, :session_length_in_minutes, :bigint, unsigned: true, null: true
  end
end
