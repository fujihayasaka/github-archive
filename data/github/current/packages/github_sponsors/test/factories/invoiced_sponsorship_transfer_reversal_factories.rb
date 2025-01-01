# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :invoiced_sponsorship_transfer_reversal do
    invoiced_sponsorship_transfer { create(:invoiced_sponsorship_transfer, :completed) }
    actor { create(:staff_admin_user) }
    amount_in_cents { 100_00 }

    trait :completed do
      sequence :stripe_transfer_reversal_id do |n|
        "trr_00000#{n}"
      end

      transfer_reversal_created_at { Time.parse("2020-11-02T12:00:00Z") }
    end
  end
end
