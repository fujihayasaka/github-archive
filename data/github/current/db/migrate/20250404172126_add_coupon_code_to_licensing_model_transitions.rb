# typed: strict
# frozen_string_literal: true

class AddCouponCodeToLicensingModelTransitions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  sig { void }
  def change
    change_table :licensing_model_transitions, bulk: true do |t|
      t.string :coupon_code, null: true, limit: 255, default: nil
    end
  end
end
