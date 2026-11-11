# typed: strict
# frozen_string_literal: true

class AddUnbundleGhasToLicensingModelTransitions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Billing)

  sig { void }
  def change
    change_table :licensing_model_transitions, bulk: true do |t|
      t.boolean :unbundle_ghas, default: false, null: false
    end
  end
end
