# typed: true
# frozen_string_literal: true

class AddEncodedSocialAccountsToProfiles < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :profiles, :encoded_social_accounts, :json
  end
end
