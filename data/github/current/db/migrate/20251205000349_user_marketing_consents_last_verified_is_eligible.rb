# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/AvoidRedundantIndex
class UserMarketingConsentsLastVerifiedIsEligible < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::SignupFlow)

  def up
    change_table :user_marketing_consents, bulk: true do |t|
      t.column :last_verified_with_cpm_at, :timestamp, null: true, default: nil
      t.column :is_eligible_for_nurture_campaign, :boolean, null: false, default: false
      t.index [:created_at, :is_eligible_for_nurture_campaign], name: "idx_umc_createdat_eligible"
      t.index [:marketing_consent, :is_eligible_for_nurture_campaign, :created_at], name: "idx_umc_mc_iseligible_createdat"
      t.remove_index name: "index_umc_on_mc_and_optout_and_created"
      t.remove_index name: "index_user_marketing_consents_on_updated_at"
      t.remove_index name: "index_user_marketing_consents_on_created_at"
    end
  end

  def down
    change_table :user_marketing_consents, bulk: true do |t|
      t.remove :last_verified_with_cpm_at
      t.remove :is_eligible_for_nurture_campaign
      t.remove_index name: "idx_umc_createdat_eligible"
      t.remove_index name: "idx_umc_mc_iseligible_createdat"
      t.index [:marketing_consent, :onboarding_optout_date, :created_at], name: "index_umc_on_mc_and_optout_and_created"
      t.index :updated_at, name: "index_user_marketing_consents_on_updated_at"
      t.index name: "index_user_marketing_consents_on_created_at"
    end
  end
end
