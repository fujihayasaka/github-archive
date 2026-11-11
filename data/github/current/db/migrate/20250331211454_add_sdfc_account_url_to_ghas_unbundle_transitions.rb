# typed: strict
# frozen_string_literal: true

class AddSdfcAccountUrlToGhasUnbundleTransitions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)

  sig { void }
  def change
    change_table :ghas_unbundle_transitions, bulk: true do |t|
      t.text :sfdc_account_url, null: true
    end
  end
end
