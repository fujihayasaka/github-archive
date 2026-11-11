# typed: true
# frozen_string_literal: true

class AddEnterpriseAgreementNumberToVssSubscriptionEvents < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :vss_subscription_events, bulk: true do |t|
      t.column :enterprise_agreement_number, :string,
        limit: 255,
        as: "parsed_payload->>'$.AgreementNumber'",
        stored: true

      t.index :enterprise_agreement_number
    end
  end
end
