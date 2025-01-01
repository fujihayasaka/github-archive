# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddDemoOnboardingUrlToListings < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    change_table :marketplace_listings, bulk: true do |t|
      t.column :demo_url, :text, default: nil
      t.column :onboarding_url, :text, default: nil
    end
  end
end
